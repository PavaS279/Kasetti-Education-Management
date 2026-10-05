/**
 * Family messaging (F2.5): templated notifications for business events, staff
 * messages, consent, and email delivery.
 *
 * Every message is a Message__c record (the outbox and the audit trail):
 *  - Portal: shown in the family portal inbox (Delivered at once).
 *  - Email: Queued, then sent by DispatchJob. It is Suppressed when the
 *    recipient opted out of email or has no address, and Not Sent while the
 *    Education Setting Email_Delivery is Off.
 * Templates are Message_Template__mdt records named after the event. Dedup_Key__c
 * (unique) guarantees a notification is never created twice for the same event,
 * channel, recipient and record, so retries and the reminder job are idempotent.
 *
 * Notifications never break the business transaction that raised them: event
 * entry points catch and log every failure.
 */
public with sharing class MessageService {
  public static final String STAFF_EVENT = 'Staff Message';
  public static final String EMAIL = 'Email';
  public static final String PORTAL = 'Portal';
  private static final Integer DISPATCH_BATCH = 100;

  @TestVisible
  private static Map<String, Message_Template__mdt> templates;
  /** Lets tests of other features run many operations in one transaction. */
  @TestVisible
  private static Boolean disabled = false;

  /** One message to render: who receives it, about whom, and the merge values. */
  public class Notice {
    public Id recipientId;
    public Id learnerContactId;
    public Id learnerAccountId;
    public Id branchId;
    public Id relatedId;
    /** Distinguishes repeat notifications for the same record (e.g. due date and reminder day). */
    public String dedupSuffix = '';
    public Map<String, String> values = new Map<String, String>();
  }

  public class StaffMessage {
    @AuraEnabled
    public Id learnerAccountId { get; set; }
    @AuraEnabled
    public Id recipientId { get; set; }
    /** Email, Portal or Both. */
    @AuraEnabled
    public String channel { get; set; }
    @AuraEnabled
    public String subject { get; set; }
    @AuraEnabled
    public String body { get; set; }
  }

  public class Recipient {
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public Boolean optedOut;
    @AuraEnabled
    public Boolean feePayer;
  }

  public class Timeline {
    @AuraEnabled
    public List<Message__c> messages;
    @AuraEnabled
    public List<Recipient> recipients;
    @AuraEnabled
    public Boolean emailLive;
    @AuraEnabled
    public Boolean canManageConsent;
  }

  // ----------------------------------------------------------- event hooks

  public static void invoicesIssued(Set<Id> invoiceIds) {
    try {
      send('Invoice_Issued', invoiceNotices(invoiceIds, null, null));
    } catch (Exception e) {
      Logger.error('MessageService.invoicesIssued', e, null);
    }
  }

  public static void paymentsReceived(Set<Id> paymentIds) {
    try {
      List<Notice> notices = new List<Notice>();
      for (Student_Payment__c payment : [
        SELECT
          Id,
          Payer__c,
          Learner__c,
          Learner__r.Name,
          Branch__c,
          Amount__c,
          Method__c,
          Payment_Date__c,
          Receipt_Number__c,
          Student_Invoice__r.Name,
          Student_Invoice__r.Learner_Account__c
        FROM Student_Payment__c
        WHERE
          Id IN :paymentIds
          AND Status__c = 'Confirmed'
          AND Method__c != :CreditService.CREDIT_METHOD
        WITH SYSTEM_MODE
      ]) {
        Notice notice = new Notice();
        notice.recipientId = payment.Payer__c;
        notice.learnerContactId = payment.Learner__c;
        notice.learnerAccountId = payment.Student_Invoice__r
          ?.Learner_Account__c;
        notice.branchId = payment.Branch__c;
        notice.relatedId = payment.Id;
        notice.values.put('LearnerName', payment.Learner__r?.Name);
        notice.values.put('ReceiptNumber', payment.Receipt_Number__c);
        notice.values.put('Amount', money(payment.Amount__c));
        notice.values.put('Method', payment.Method__c);
        notice.values.put('PaymentDate', dateText(payment.Payment_Date__c));
        notice.values.put('InvoiceNumber', payment.Student_Invoice__r?.Name);
        notices.add(notice);
      }
      send('Payment_Received', notices);
    } catch (Exception e) {
      Logger.error('MessageService.paymentsReceived', e, null);
    }
  }

  public static void waitlistOffers(Set<Id> entryIds) {
    try {
      List<Waitlist_Entry__c> entries = [
        SELECT
          Id,
          Learner__c,
          Learner_Contact__c,
          Learner_Contact__r.Name,
          Branch__c,
          Branch__r.Name,
          Course_Offering__r.Name,
          Offer_Expires__c,
          Offers_Made__c
        FROM Waitlist_Entry__c
        WHERE Id IN :entryIds AND Status__c = 'Offered'
        WITH SYSTEM_MODE
      ];
      Set<Id> learners = new Set<Id>();
      for (Waitlist_Entry__c entry : entries) {
        learners.add(entry.Learner_Contact__c);
      }
      Map<Id, Id> payers = feePayers(learners);
      List<Notice> notices = new List<Notice>();
      for (Waitlist_Entry__c entry : entries) {
        Notice notice = new Notice();
        notice.recipientId = payers.get(entry.Learner_Contact__c);
        notice.learnerContactId = entry.Learner_Contact__c;
        notice.learnerAccountId = entry.Learner__c;
        notice.branchId = entry.Branch__c;
        notice.relatedId = entry.Id;
        notice.dedupSuffix = String.valueOf(entry.Offers_Made__c);
        notice.values.put('LearnerName', entry.Learner_Contact__r?.Name);
        notice.values.put('BranchName', entry.Branch__r?.Name);
        notice.values.put('ClassName', entry.Course_Offering__r?.Name);
        notice.values.put(
          'OfferExpires',
          entry.Offer_Expires__c == null ? '' : entry.Offer_Expires__c.format()
        );
        notices.add(notice);
      }
      send('Waitlist_Offer', notices);
    } catch (Exception e) {
      Logger.error('MessageService.waitlistOffers', e, null);
    }
  }

  public static void refundsPaid(Set<Id> refundIds) {
    try {
      List<Notice> notices = new List<Notice>();
      for (Refund__c refund : [
        SELECT
          Id,
          Payee__c,
          Branch__c,
          Amount__c,
          Method__c,
          Reference__c,
          Credit_Note__r.Name,
          Credit_Note__r.Learner__c,
          Credit_Note__r.Learner__r.Name,
          Credit_Note__r.Learner_Account__c
        FROM Refund__c
        WHERE Id IN :refundIds AND Status__c = 'Paid'
        WITH SYSTEM_MODE
      ]) {
        Notice notice = new Notice();
        notice.recipientId = refund.Payee__c;
        notice.learnerContactId = refund.Credit_Note__r?.Learner__c;
        notice.learnerAccountId = refund.Credit_Note__r?.Learner_Account__c;
        notice.branchId = refund.Branch__c;
        notice.relatedId = refund.Id;
        notice.values.put(
          'LearnerName',
          refund.Credit_Note__r?.Learner__r?.Name
        );
        notice.values.put('Amount', money(refund.Amount__c));
        notice.values.put('Method', refund.Method__c);
        notice.values.put('Reference', refund.Reference__c);
        notice.values.put('CreditNoteNumber', refund.Credit_Note__r?.Name);
        notices.add(notice);
      }
      send('Refund_Paid', notices);
    } catch (Exception e) {
      Logger.error('MessageService.refundsPaid', e, null);
    }
  }

  /** Tells each enrolled learner's fee payer that a session was cancelled. */
  public static void sessionCancelled(Id sessionId) {
    try {
      Class_Session__c session = [
        SELECT
          Id,
          Start__c,
          Branch__c,
          Cancellation_Reason__c,
          Course_Offering__c,
          Course_Offering__r.Name
        FROM Class_Session__c
        WHERE Id = :sessionId
        WITH SYSTEM_MODE
      ];
      List<CourseOfferingParticipant> learners = [
        SELECT
          ParticipantContactId,
          ParticipantContact.Name,
          ParticipantAccountId
        FROM CourseOfferingParticipant
        WHERE
          CourseOfferingId = :session.Course_Offering__c
          AND ParticipationStatus IN :SeatService.SEAT_STATUSES
        WITH SYSTEM_MODE
      ];
      Set<Id> contacts = new Set<Id>();
      for (CourseOfferingParticipant learner : learners) {
        contacts.add(learner.ParticipantContactId);
      }
      Map<Id, Id> payers = feePayers(contacts);
      List<Notice> notices = new List<Notice>();
      for (CourseOfferingParticipant learner : learners) {
        Notice notice = new Notice();
        notice.recipientId = payers.get(learner.ParticipantContactId);
        notice.learnerContactId = learner.ParticipantContactId;
        notice.learnerAccountId = learner.ParticipantAccountId;
        notice.branchId = session.Branch__c;
        notice.relatedId = session.Id;
        notice.dedupSuffix = learner.ParticipantContactId;
        notice.values.put('LearnerName', learner.ParticipantContact?.Name);
        notice.values.put('ClassName', session.Course_Offering__r?.Name);
        notice.values.put(
          'SessionDate',
          session.Start__c == null ? '' : session.Start__c.format()
        );
        notice.values.put('Reason', session.Cancellation_Reason__c);
        notices.add(notice);
      }
      send('Session_Cancelled', notices);
    } catch (Exception e) {
      Logger.error('MessageService.sessionCancelled', e, sessionId);
    }
  }

  /**
   * Daily payment reminders: invoices due in Due_Soon_Days days, and overdue
   * invoices on each day listed in Overdue_Reminder_Days. Returns the number of
   * messages created (repeats are skipped by the dedup key).
   */
  public static Integer sendReminders(Date today) {
    Integer created = 0;
    Date dueSoon = today.addDays(AppSettings.getInteger('Due_Soon_Days', 3));
    created += send(
        'Invoice_Due_Soon',
        invoiceNotices(dueInvoices(new Set<Date>{ dueSoon }), today, null)
      )
      .size();
    Map<Date, Integer> overdueDays = new Map<Date, Integer>();
    for (
      String part : AppSettings.getString('Overdue_Reminder_Days', '1,7,14')
        .split(',')
    ) {
      if (part.trim().isNumeric()) {
        Integer days = Integer.valueOf(part.trim());
        overdueDays.put(today.addDays(-days), days);
      }
    }
    if (!overdueDays.isEmpty()) {
      created += send(
          'Invoice_Overdue',
          invoiceNotices(dueInvoices(overdueDays.keySet()), today, overdueDays)
        )
        .size();
    }
    return created;
  }

  // -------------------------------------------------------- staff messages

  /** A message written by staff to the learner or one of their guardians. */
  public static List<Id> sendStaffMessage(StaffMessage request) {
    if (request == null || request.learnerAccountId == null) {
      throw new AppException('Choose the learner.');
    }
    if (request.recipientId == null) {
      throw new AppException('Choose who receives the message.');
    }
    if (String.isBlank(request.subject) || String.isBlank(request.body)) {
      throw new AppException('Enter a subject and a message.');
    }
    String channel = String.isBlank(request.channel) ? 'Both' : request.channel;
    if (!new Set<String>{ EMAIL, PORTAL, 'Both' }.contains(channel)) {
      throw new AppException('Choose Email, Portal or Both.');
    }
    assertReadable(request.learnerAccountId);
    Account learner = [
      SELECT Id, PersonContactId, Branch__c
      FROM Account
      WHERE Id = :request.learnerAccountId
      WITH SYSTEM_MODE
    ];
    Boolean known = false;
    for (Recipient option : recipientsFor(learner)) {
      known |= option.contactId == request.recipientId;
    }
    if (!known) {
      throw new AppException(
        'Messages can only go to the learner or one of their guardians.'
      );
    }
    Notice notice = new Notice();
    notice.recipientId = request.recipientId;
    notice.learnerContactId = learner.PersonContactId;
    notice.learnerAccountId = learner.Id;
    notice.branchId = learner.Branch__c;
    Message_Template__mdt adHoc = new Message_Template__mdt(
      DeveloperName = STAFF_EVENT,
      Subject__c = request.subject.left(255),
      Body__c = request.body,
      Active__c = true,
      Send_Email__c = channel != PORTAL,
      Send_Portal__c = channel != EMAIL
    );
    List<Id> ids = new List<Id>();
    for (Message__c message : create(adHoc, new List<Notice>{ notice }, true)) {
      ids.add(message.Id);
    }
    return ids;
  }

  // -------------------------------------------------------------- consent

  /** Records an email opt-out (or opt-in) for the learner or one of their guardians. */
  public static void setEmailOptOut(
    Id learnerAccountId,
    Id contactId,
    Boolean optedOut
  ) {
    assertReadable(learnerAccountId);
    Account learner = [
      SELECT Id, PersonContactId, Branch__c
      FROM Account
      WHERE Id = :learnerAccountId
      WITH SYSTEM_MODE
    ];
    Boolean known = false;
    for (Recipient option : recipientsFor(learner)) {
      known |= option.contactId == contactId;
    }
    if (!known) {
      throw new AppException('Choose the learner or one of their guardians.');
    }
    Contact person = [
      SELECT Id, AccountId, IsPersonAccount
      FROM Contact
      WHERE Id = :contactId
      WITH SYSTEM_MODE
    ];
    // Consent changes are made as the user (field-level and record access apply).
    if (person.IsPersonAccount) {
      Database.update(
        new Account(
          Id = person.AccountId,
          PersonHasOptedOutOfEmail = optedOut == true
        ),
        AccessLevel.USER_MODE
      );
    } else {
      Database.update(
        new Contact(Id = contactId, HasOptedOutOfEmail = optedOut == true),
        AccessLevel.USER_MODE
      );
    }
  }

  // ----------------------------------------------------------------- reads

  /** Messages about a learner (to the learner or their family), newest first. */
  public static Timeline timeline(Id learnerAccountId) {
    assertReadable(learnerAccountId);
    Account learner = [
      SELECT Id, PersonContactId, Branch__c
      FROM Account
      WHERE Id = :learnerAccountId
      WITH SYSTEM_MODE
    ];
    Timeline result = new Timeline();
    result.messages = [
      SELECT
        Id,
        Name,
        Channel__c,
        Event__c,
        Subject__c,
        Body__c,
        Status__c,
        Status_Detail__c,
        Sent_On__c,
        Read_On__c,
        CreatedDate,
        Recipient__c,
        Recipient__r.Name,
        Sent_By__r.Name
      FROM Message__c
      WHERE
        Learner_Account__c = :learnerAccountId
        OR Recipient__c = :learner.PersonContactId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 200
    ];
    result.recipients = recipientsFor(learner);
    result.emailLive = emailLive();
    result.canManageConsent = Schema.SObjectType.Contact.fields.HasOptedOutOfEmail.isUpdateable();
    return result;
  }

  // -------------------------------------------------------------- delivery

  /** Sends queued emails (oldest first). Returns how many were sent. */
  public static Integer dispatch(Integer maxMessages) {
    List<Message__c> queued = [
      SELECT Id, Recipient__c, Subject__c, Body__c, Branch__r.Name
      FROM Message__c
      WHERE Status__c = 'Queued' AND Channel__c = :EMAIL
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT :maxMessages
    ];
    if (queued.isEmpty()) {
      return 0;
    }
    List<Message__c> updates = new List<Message__c>();
    if (!emailLive()) {
      for (Message__c message : queued) {
        updates.add(notSent(message.Id));
      }
      new Writer().updateRecords(updates);
      return 0;
    }
    List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
    for (Message__c message : queued) {
      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
      email.setTargetObjectId(message.Recipient__c);
      email.setSaveAsActivity(false);
      email.setSubject(message.Subject__c);
      email.setPlainTextBody(message.Body__c);
      email.setHtmlBody(htmlBody(message.Body__c, message.Branch__r?.Name));
      email.setSenderDisplayName(
        message.Branch__r?.Name == null
          ? 'Kasetti Education'
          : message.Branch__r.Name
      );
      emails.add(email);
    }
    Integer sent = 0;
    List<Messaging.SendEmailResult> results;
    try {
      results = Messaging.sendEmail(emails, false);
    } catch (Exception e) {
      // Limits or deliverability: everything in this batch failed.
      for (Message__c message : queued) {
        updates.add(failed(message.Id, e.getMessage()));
      }
      new Writer().updateRecords(updates);
      Logger.error('MessageService.dispatch', e, null);
      return 0;
    }
    for (Integer i = 0; i < queued.size(); i++) {
      if (results[i].isSuccess()) {
        sent++;
        updates.add(
          new Message__c(
            Id = queued[i].Id,
            Status__c = 'Sent',
            Sent_On__c = System.now()
          )
        );
      } else {
        updates.add(
          failed(queued[i].Id, results[i].getErrors()[0].getMessage())
        );
      }
    }
    new Writer().updateRecords(updates);
    return sent;
  }

  /** Queues delivery unless already in an async context that cannot start more jobs. */
  private static void dispatchAsync() {
    if (
      System.isBatch() ||
      System.isFuture() ||
      Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
    ) {
      return; // the hourly KEM Message Dispatch job picks these up
    }
    System.enqueueJob(new DispatchJob());
  }

  public class DispatchJob implements Queueable {
    public void execute(QueueableContext context) {
      dispatch(DISPATCH_BATCH);
      Logger.flush();
    }
  }

  // ------------------------------------------------------------- creation

  @TestVisible
  private static List<Message__c> send(String eventKey, List<Notice> notices) {
    if (disabled || notices.isEmpty()) {
      return new List<Message__c>();
    }
    Message_Template__mdt template = templateFor(eventKey);
    if (template == null || template.Active__c != true) {
      return new List<Message__c>();
    }
    return create(template, notices, false);
  }

  private static List<Message__c> create(
    Message_Template__mdt template,
    List<Notice> notices,
    Boolean staff
  ) {
    Set<Id> recipientIds = new Set<Id>();
    Set<Id> branchIds = new Set<Id>();
    for (Notice notice : notices) {
      recipientIds.add(notice.recipientId);
      if (notice.values.get('BranchName') == null) {
        branchIds.add(notice.branchId);
      }
    }
    recipientIds.remove(null);
    branchIds.remove(null);
    Map<Id, Contact> recipients = new Map<Id, Contact>(
      [
        SELECT Id, FirstName, Name, Email, HasOptedOutOfEmail
        FROM Contact
        WHERE Id IN :recipientIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Branch__c> branches = branchIds.isEmpty()
      ? new Map<Id, Branch__c>()
      : new Map<Id, Branch__c>(
          [
            SELECT Id, Name
            FROM Branch__c
            WHERE Id IN :branchIds
            WITH SYSTEM_MODE
          ]
        );
    Boolean live = emailLive();
    String portalUrl = AppSettings.getString('Portal_URL', '');
    List<Message__c> messages = new List<Message__c>();
    for (Notice notice : notices) {
      Contact recipient = recipients.get(notice.recipientId);
      if (recipient == null) {
        continue;
      }
      Map<String, String> values = notice.values.clone();
      values.put(
        'RecipientFirstName',
        String.isBlank(recipient.FirstName)
          ? recipient.Name
          : recipient.FirstName
      );
      if (values.get('BranchName') == null) {
        values.put(
          'BranchName',
          branches.containsKey(notice.branchId)
            ? branches.get(notice.branchId).Name
            : 'Kasetti Education'
        );
      }
      values.put('PortalLink', portalUrl);
      String subject = render(template.Subject__c, values).left(255);
      String body = render(template.Body__c, values);
      if (template.Send_Portal__c == true) {
        Message__c inbox = message(
          template,
          notice,
          PORTAL,
          subject,
          body,
          staff
        );
        inbox.Status__c = 'Delivered';
        inbox.Sent_On__c = System.now();
        messages.add(inbox);
      }
      if (template.Send_Email__c == true) {
        Message__c email = message(
          template,
          notice,
          EMAIL,
          subject,
          body,
          staff
        );
        if (String.isBlank(recipient.Email)) {
          email.Status__c = 'Suppressed';
          email.Status_Detail__c = 'No email address on record.';
        } else if (recipient.HasOptedOutOfEmail) {
          email.Status__c = 'Suppressed';
          email.Status_Detail__c = 'The recipient has opted out of email.';
        } else if (!live) {
          email.Status__c = 'Not Sent';
          email.Status_Detail__c = notSent(null).Status_Detail__c;
        } else {
          email.Status__c = 'Queued';
        }
        messages.add(email);
      }
    }
    if (messages.isEmpty()) {
      return messages;
    }
    List<Message__c> created = new List<Message__c>();
    Boolean anyQueued = false;
    List<Database.SaveResult> results = new Writer()
      .insertAllowingDuplicates(messages);
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        created.add(messages[i]);
        anyQueued |= messages[i].Status__c == 'Queued';
      } else if (
        results[i].getErrors()[0].getStatusCode() != StatusCode.DUPLICATE_VALUE
      ) {
        Logger.error(
          'MessageService.create',
          new AppException(results[i].getErrors()[0].getMessage()),
          messages[i].Related_Record_Id__c
        );
      }
    }
    if (anyQueued) {
      dispatchAsync();
    }
    return created;
  }

  private static Message__c message(
    Message_Template__mdt template,
    Notice notice,
    String channel,
    String subject,
    String body,
    Boolean staff
  ) {
    return new Message__c(
      Recipient__c = notice.recipientId,
      Learner__c = notice.learnerContactId,
      Learner_Account__c = notice.learnerAccountId,
      Branch__c = notice.branchId,
      Channel__c = channel,
      Event__c = template.DeveloperName,
      Subject__c = subject,
      Body__c = body,
      Related_Record_Id__c = notice.relatedId,
      Sent_By__c = staff ? UserInfo.getUserId() : null,
      Dedup_Key__c = staff
        ? null
        : (template.DeveloperName +
            '|' +
            channel +
            '|' +
            notice.recipientId +
            '|' +
            notice.relatedId +
            '|' +
            notice.dedupSuffix)
            .left(150)
    );
  }

  /** Replaces {{Token}} with its value; unknown tokens become empty. */
  @TestVisible
  private static String render(String text, Map<String, String> values) {
    if (text == null) {
      return '';
    }
    String result = text;
    for (String key : values.keySet()) {
      String value = values.get(key);
      result = result.replace('{{' + key + '}}', value == null ? '' : value);
    }
    return result.replaceAll('\\{\\{\\w+\\}\\}', '');
  }

  private static String htmlBody(String body, String branchName) {
    String safe = body == null ? '' : body.escapeHtml4().replace('\n', '<br/>');
    return '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#16243a;max-width:600px">' +
      '<div style="background:#1b3a6b;color:#ffffff;padding:16px 20px;border-radius:8px 8px 0 0;font-weight:bold">' +
      (branchName == null ? 'Kasetti Education' : branchName.escapeHtml4()) +
      '</div><div style="border:1px solid #e3e8ef;border-top:none;padding:20px;border-radius:0 0 8px 8px;line-height:1.5">' +
      safe +
      '</div></div>';
  }

  // --------------------------------------------------------------- helpers

  private static List<Notice> invoiceNotices(
    Set<Id> invoiceIds,
    Date today,
    Map<Date, Integer> overdueDays
  ) {
    List<Notice> notices = new List<Notice>();
    if (invoiceIds.isEmpty()) {
      return notices;
    }
    for (Student_Invoice__c invoice : [
      SELECT
        Id,
        Name,
        Bill_To__c,
        Learner__c,
        Learner__r.Name,
        Learner_Account__c,
        Branch__c,
        Branch__r.Name,
        Total__c,
        Balance_Due__c,
        Due_Date__c,
        Billing_Period__c,
        Enrolment__r.CourseOffering.Name
      FROM Student_Invoice__c
      WHERE Id IN :invoiceIds AND Status__c IN :BillingService.OPEN_STATUSES
      WITH SYSTEM_MODE
    ]) {
      Notice notice = new Notice();
      notice.recipientId = invoice.Bill_To__c;
      notice.learnerContactId = invoice.Learner__c;
      notice.learnerAccountId = invoice.Learner_Account__c;
      notice.branchId = invoice.Branch__c;
      notice.relatedId = invoice.Id;
      notice.values.put('LearnerName', invoice.Learner__r?.Name);
      notice.values.put('InvoiceNumber', invoice.Name);
      notice.values.put('BranchName', invoice.Branch__r?.Name);
      notice.values.put(
        'ClassName',
        invoice.Enrolment__r?.CourseOffering?.Name
      );
      notice.values.put('Amount', money(invoice.Total__c));
      notice.values.put('BalanceDue', money(invoice.Balance_Due__c));
      notice.values.put('DueDate', dateText(invoice.Due_Date__c));
      notice.values.put(
        'BillingPeriod',
        String.isBlank(invoice.Billing_Period__c)
          ? ''
          : ', ' + invoice.Billing_Period__c
      );
      if (today != null) {
        notice.dedupSuffix = String.valueOf(invoice.Due_Date__c);
      }
      if (overdueDays != null) {
        Integer days = overdueDays.get(invoice.Due_Date__c);
        notice.values.put('DaysOverdue', String.valueOf(days));
        notice.dedupSuffix += '|' + days;
      }
      notices.add(notice);
    }
    return notices;
  }

  private static Set<Id> dueInvoices(Set<Date> dueDates) {
    return new Map<Id, Student_Invoice__c>(
        [
          SELECT Id
          FROM Student_Invoice__c
          WHERE
            Status__c IN :BillingService.OPEN_STATUSES
            AND Due_Date__c IN :dueDates
            AND Balance_Due__c > 0
          WITH SYSTEM_MODE
          LIMIT 2000
        ]
      )
      .keySet();
  }

  /** Fee payer of each learner contact (the learner when no fee-paying guardian is set). */
  private static Map<Id, Id> feePayers(Set<Id> learnerContactIds) {
    Map<Id, Id> payers = new Map<Id, Id>();
    for (Id learnerId : learnerContactIds) {
      payers.put(learnerId, learnerId);
    }
    for (ContactContactRelation rel : [
      SELECT ContactId, RelatedContactId
      FROM ContactContactRelation
      WHERE
        RelatedContactId IN :learnerContactIds
        AND PartyRoleRelationId = :GuardianRelationshipService.guardianRoleRelationId()
        AND IsActive = TRUE
        AND Is_Fee_Payer__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
    ]) {
      payers.put(rel.RelatedContactId, rel.ContactId);
    }
    return payers;
  }

  /** The learner and their active guardians, with email consent. */
  private static List<Recipient> recipientsFor(Account learner) {
    Map<Id, Recipient> byContact = new Map<Id, Recipient>();
    Map<Id, String> roles = new Map<Id, String>{
      learner.PersonContactId => 'Learner'
    };
    Set<Id> payers = new Set<Id>();
    for (ContactContactRelation rel : [
      SELECT ContactId, Guardian_Relationship__c, Is_Fee_Payer__c
      FROM ContactContactRelation
      WHERE
        RelatedContactId = :learner.PersonContactId
        AND PartyRoleRelationId = :GuardianRelationshipService.guardianRoleRelationId()
        AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      roles.put(
        rel.ContactId,
        String.isBlank(rel.Guardian_Relationship__c)
          ? 'Guardian'
          : rel.Guardian_Relationship__c
      );
      if (rel.Is_Fee_Payer__c) {
        payers.add(rel.ContactId);
      }
    }
    for (Contact person : [
      SELECT Id, Name, Email, HasOptedOutOfEmail
      FROM Contact
      WHERE Id IN :roles.keySet()
      WITH SYSTEM_MODE
    ]) {
      Recipient option = new Recipient();
      option.contactId = person.Id;
      option.name = person.Name;
      option.role = roles.get(person.Id);
      option.email = person.Email;
      option.optedOut = person.HasOptedOutOfEmail;
      option.feePayer = payers.contains(person.Id);
      byContact.put(person.Id, option);
    }
    return byContact.values();
  }

  private static void assertReadable(Id recordId) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasReadAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
    ];
    if (access.isEmpty() || !access[0].HasReadAccess) {
      throw new AppException('Learner not found or not accessible.');
    }
  }

  private static Message_Template__mdt templateFor(String eventKey) {
    if (templates == null) {
      // Queried rather than getAll(): getAll() truncates long text fields to 255
      // characters. Custom metadata queries do not count against SOQL limits.
      templates = new Map<String, Message_Template__mdt>();
      for (Message_Template__mdt template : [
        SELECT
          DeveloperName,
          Subject__c,
          Body__c,
          Active__c,
          Send_Email__c,
          Send_Portal__c
        FROM Message_Template__mdt
      ]) {
        templates.put(template.DeveloperName, template);
      }
    }
    return templates.get(eventKey);
  }

  public static Boolean emailLive() {
    return AppSettings.getString('Email_Delivery', 'Off') == 'Live';
  }

  private static Message__c notSent(Id messageId) {
    return new Message__c(
      Id = messageId,
      Status__c = 'Not Sent',
      Status_Detail__c = 'Email delivery is switched off (Education Setting Email_Delivery).'
    );
  }

  private static Message__c failed(Id messageId, String detail) {
    return new Message__c(
      Id = messageId,
      Status__c = 'Failed',
      Status_Detail__c = detail == null ? null : detail.left(255)
    );
  }

  /** ₹ with grouping in the user's locale and always two decimals. */
  @TestVisible
  private static String money(Decimal amount) {
    if (amount == null) {
      return '';
    }
    Decimal value = amount.setScale(2);
    String fraction = String.valueOf(value).substringAfter('.');
    return '₹' + value.longValue().format() + '.' + fraction;
  }

  private static String dateText(Date value) {
    return value == null ? '' : value.format();
  }

  /** Message writes: system-managed outbox, authorised by the event or the staff check above. */
  private without sharing class Writer {
    List<Database.SaveResult> insertAllowingDuplicates(
      List<Message__c> records
    ) {
      return Database.insert(records, false, AccessLevel.SYSTEM_MODE);
    }

    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
