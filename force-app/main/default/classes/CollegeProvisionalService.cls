/**
 * Provisional college enrolments after admission: nightly expiry, the Dean's
 * overdue list (extend or cancel), payment-due reminders and the admission
 * confirmed / expired / cancelled messages. Every transition locks the
 * programme enrolment and is a no-op when it already happened.
 */
public without sharing class CollegeProvisionalService {
  public static final String DEAN_PERMISSION = InterviewService.PERMISSION;
  public static final Set<String> INSTRUMENT_METHODS = new Set<String>{
    'Cheque',
    'Demand Draft'
  };
  public static final Integer REMINDER_DAYS = 2;

  public class OverdueRow {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public String studentName;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String campusName;
    @AuraEnabled
    public Date paymentDueBy;
    @AuraEnabled
    public Decimal paid;
    @AuraEnabled
    public Decimal awaitingClearance;
    @AuraEnabled
    public Decimal balanceDue;
  }

  // ------------------------------------------------------------ nightly work

  /** Provisional enrolments past their payment date: expires those with nothing paid or pending. Returns the number expired. */
  public static Integer processOverdue(
    List<Programme_Enrolment__c> scope,
    Date today
  ) {
    Set<Id> candidates = new Set<Id>();
    for (Programme_Enrolment__c value : scope) {
      if (
        value.Status__c == 'Provisional' &&
        value.Payment_Due_By__c != null &&
        value.Payment_Due_By__c < today
      ) {
        candidates.add(value.Id);
      }
    }
    Map<Id, Money> money = moneyFor(candidates);
    Integer expired = 0;
    for (Id enrolmentId : candidates) {
      Money m = money.get(enrolmentId);
      if (m.paid > 0 || m.pending > 0) {
        continue; // waits on the Dean's overdue list
      }
      Savepoint checkpoint = Database.setSavepoint();
      try {
        if (close(enrolmentId, 'Expired', 'Payment window expired', today)) {
          expired++;
        }
      } catch (Exception failure) {
        Database.rollback(checkpoint);
        Logger.error(
          'CollegeProvisionalService.processOverdue',
          failure,
          enrolmentId
        );
      }
    }
    Logger.flush();
    return expired;
  }

  /** Reminds the fee payer two days before the payment date, once per due date. */
  public static Integer sendReminders(
    List<Programme_Enrolment__c> scope,
    Date today
  ) {
    List<Programme_Enrolment__c> due = new List<Programme_Enrolment__c>();
    for (Programme_Enrolment__c value : scope) {
      if (
        value.Status__c == 'Provisional' &&
        value.Expiry_Reminder_Sent__c != true &&
        value.Payment_Due_By__c == today.addDays(REMINDER_DAYS)
      ) {
        due.add(value);
      }
    }
    if (due.isEmpty()) {
      return 0;
    }
    notify('College_Payment_Due_Soon', idsOf(due), null);
    List<Programme_Enrolment__c> flags = new List<Programme_Enrolment__c>();
    for (Programme_Enrolment__c value : due) {
      flags.add(
        new Programme_Enrolment__c(
          Id = value.Id,
          Expiry_Reminder_Sent__c = true
        )
      );
    }
    Database.update(flags, AccessLevel.SYSTEM_MODE);
    return due.size();
  }

  /** Called after a roll number is issued: tells the student once. */
  public static void confirmAdmissions(Set<Id> enrolmentIds) {
    List<Programme_Enrolment__c> pending = [
      SELECT Id
      FROM Programme_Enrolment__c
      WHERE
        Id IN :enrolmentIds
        AND Status__c = 'Enrolled'
        AND Confirmation_Sent__c = FALSE
      WITH SYSTEM_MODE
    ];
    if (pending.isEmpty()) {
      return;
    }
    notify('College_Admission_Confirmed', idsOf(pending), null);
    for (Programme_Enrolment__c value : pending) {
      value.Confirmation_Sent__c = true;
    }
    Database.update(pending, AccessLevel.SYSTEM_MODE);
  }

  // ------------------------------------------------------------ Dean actions

  /** Provisional enrolments past their payment date that were not expired because money is paid or awaiting clearance. */
  public static List<OverdueRow> overdueList() {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    Map<Id, Programme_Enrolment__c> overdue = new Map<Id, Programme_Enrolment__c>(
      [
        SELECT
          Id,
          Payment_Due_By__c,
          Student__r.Name,
          Branch__r.Name,
          Campus__r.Name
        FROM Programme_Enrolment__c
        WHERE Status__c = 'Provisional' AND Payment_Due_By__c < TODAY
        WITH USER_MODE
        ORDER BY Payment_Due_By__c
        LIMIT 200
      ]
    );
    Map<Id, Money> money = moneyFor(overdue.keySet());
    List<OverdueRow> rows = new List<OverdueRow>();
    for (Programme_Enrolment__c value : overdue.values()) {
      Money m = money.get(value.Id);
      OverdueRow row = new OverdueRow();
      row.enrolmentId = value.Id;
      row.studentName = value.Student__r.Name;
      row.branchName = value.Branch__r.Name;
      row.campusName = value.Campus__r.Name;
      row.paymentDueBy = value.Payment_Due_By__c;
      row.paid = m.paid;
      row.awaitingClearance = m.pending;
      row.balanceDue = m.balance;
      rows.add(row);
    }
    return rows;
  }

  /** Dean extends the payment date of a provisional enrolment (reason recorded in field history). */
  public static void extend(Id enrolmentId, Date newDueBy, String reason) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    RecordAccess.assertEditable(enrolmentId);
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for extending the payment date.');
    }
    if (newDueBy == null || newDueBy < Date.today()) {
      throw new AppException('Choose a payment date from today onwards.');
    }
    Programme_Enrolment__c enrolment = lock(enrolmentId);
    if (enrolment.Status__c != 'Provisional') {
      throw new AppException('Only a provisional enrolment can be extended.');
    }
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolmentId,
        Payment_Due_By__c = newDueBy,
        Expiry_Reminder_Sent__c = false,
        Status_Reason__c = ('Payment date extended to ' +
          newDueBy.format() +
          ': ' +
          reason.trim())
          .left(255)
      ),
      AccessLevel.SYSTEM_MODE
    );
    for (Seat_Reservation__c reservation : [
      SELECT Id
      FROM Seat_Reservation__c
      WHERE Programme_Enrolment__c = :enrolmentId AND Status__c = 'Reserved'
      WITH SYSTEM_MODE
    ]) {
      reservation.Expires_On__c = Datetime.newInstance(
        newDueBy,
        Time.newInstance(23, 59, 59, 999)
      );
      reservation.Actioned_By__c = UserInfo.getUserId();
      Database.update(reservation, AccessLevel.SYSTEM_MODE);
    }
  }

  /** Dean cancels a provisional admission: seat released, unpaid invoices cancelled. */
  public static void cancel(Id enrolmentId, String reason) {
    RecordAccess.assertPermission(DEAN_PERMISSION);
    RecordAccess.assertEditable(enrolmentId);
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for cancelling the admission.');
    }
    Money m = moneyFor(new Set<Id>{ enrolmentId }).get(enrolmentId);
    if (m.paid > 0 || m.pending > 0) {
      throw new AppException(
        'Money is paid or awaiting clearance on this admission. Ask Accounts to fail the pending instrument or issue a credit note first.'
      );
    }
    Savepoint checkpoint = Database.setSavepoint();
    try {
      if (!close(enrolmentId, 'Cancelled', reason.trim(), Date.today())) {
        throw new AppException(
          'Only a provisional enrolment can be cancelled.'
        );
      }
    } catch (Exception failure) {
      Database.rollback(checkpoint);
      throw failure;
    }
  }

  // ------------------------------------------------------------ internals

  /** Expires or cancels one provisional enrolment atomically; false when it is no longer provisional. */
  private static Boolean close(
    Id enrolmentId,
    String target,
    String reason,
    Date today
  ) {
    Programme_Enrolment__c enrolment = lock(enrolmentId);
    if (enrolment.Status__c != 'Provisional') {
      return false;
    }
    for (Seat_Reservation__c reservation : [
      SELECT Id, Status__c
      FROM Seat_Reservation__c
      WHERE Programme_Enrolment__c = :enrolmentId
      WITH SYSTEM_MODE
    ]) {
      if (target == 'Expired') {
        CollegeSeatService.expire(reservation.Id);
      } else {
        CollegeSeatService.release(reservation.Id, reason);
      }
    }
    for (Student_Invoice__c invoice : [
      SELECT Id
      FROM Student_Invoice__c
      WHERE
        Programme_Enrolment__c = :enrolmentId
        AND Status__c IN ('Draft', 'Issued')
        AND (Amount_Paid__c = NULL
        OR Amount_Paid__c = 0)
      WITH SYSTEM_MODE
    ]) {
      BillingService.cancelSystem(
        invoice.Id,
        target == 'Expired'
          ? 'Admission payment window expired'
          : 'Admission cancelled: ' + reason
      );
    }
    Database.update(
      new Programme_Enrolment__c(
        Id = enrolmentId,
        Status__c = target,
        Status_Reason__c = reason.left(255)
      ),
      AccessLevel.SYSTEM_MODE
    );
    Database.update(
      new IndividualApplication(
        Id = enrolment.Application__c,
        College_Stage__c = 'Enrollment Failed'
      ),
      AccessLevel.SYSTEM_MODE
    );
    notify(
      target == 'Expired'
        ? 'College_Admission_Expired'
        : 'College_Admission_Cancelled',
      new Set<Id>{ enrolmentId },
      reason
    );
    return true;
  }

  private static Programme_Enrolment__c lock(Id enrolmentId) {
    return [
      SELECT Id, Status__c, Application__c
      FROM Programme_Enrolment__c
      WHERE Id = :enrolmentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  private class Money {
    Decimal paid = 0;
    Decimal pending = 0;
    Decimal balance = 0;
  }

  /** Allocated amount, DD/cheques awaiting clearance and balance per programme enrolment. */
  private static Map<Id, Money> moneyFor(Set<Id> enrolmentIds) {
    Map<Id, Money> result = new Map<Id, Money>();
    for (Id enrolmentId : enrolmentIds) {
      result.put(enrolmentId, new Money());
    }
    if (enrolmentIds.isEmpty()) {
      return result;
    }
    for (AggregateResult row : [
      SELECT
        Programme_Enrolment__c enrolment,
        SUM(Amount_Paid__c) paid,
        SUM(Balance_Due__c) balance
      FROM Student_Invoice__c
      WHERE Programme_Enrolment__c IN :enrolmentIds AND Status__c != 'Cancelled'
      WITH SYSTEM_MODE
      GROUP BY Programme_Enrolment__c
    ]) {
      Money m = result.get((Id) row.get('enrolment'));
      m.paid = nvl((Decimal) row.get('paid'));
      m.balance = nvl((Decimal) row.get('balance'));
    }
    for (AggregateResult row : [
      SELECT
        Student_Invoice__r.Programme_Enrolment__c enrolment,
        SUM(Amount__c) pending
      FROM Student_Payment__c
      WHERE
        Student_Invoice__r.Programme_Enrolment__c IN :enrolmentIds
        AND Status__c = 'Pending'
        AND Method__c IN :INSTRUMENT_METHODS
      WITH SYSTEM_MODE
      GROUP BY Student_Invoice__r.Programme_Enrolment__c
    ]) {
      result.get((Id) row.get('enrolment')).pending = nvl(
        (Decimal) row.get('pending')
      );
    }
    return result;
  }

  private static void notify(
    String eventKey,
    Set<Id> enrolmentIds,
    String reason
  ) {
    try {
      List<Programme_Enrolment__c> values = [
        SELECT
          Id,
          Status__c,
          Roll_Number__c,
          Payment_Due_By__c,
          Academic_Year__c,
          Campus__c,
          Student__c,
          Student__r.PersonContactId,
          Student__r.Name,
          Branch__r.Name,
          Programme__r.Name
        FROM Programme_Enrolment__c
        WHERE Id IN :enrolmentIds
        WITH SYSTEM_MODE
      ];
      Set<Id> contactIds = new Set<Id>();
      for (Programme_Enrolment__c value : values) {
        contactIds.add(value.Student__r.PersonContactId);
      }
      Map<Id, Id> payers = MessageService.feePayersOf(contactIds);
      Map<Id, Money> money = moneyFor(enrolmentIds);
      List<MessageService.Notice> notices = new List<MessageService.Notice>();
      for (Programme_Enrolment__c value : values) {
        Id studentContact = value.Student__r.PersonContactId;
        Set<Id> recipients = new Set<Id>{ studentContact };
        if (payers.get(studentContact) != null) {
          recipients.add(payers.get(studentContact));
        }
        for (Id recipientId : recipients) {
          MessageService.Notice notice = new MessageService.Notice();
          notice.recipientId = recipientId;
          notice.learnerContactId = studentContact;
          notice.learnerAccountId = value.Student__c;
          notice.branchId = value.Campus__c;
          notice.relatedId = value.Id;
          notice.dedupSuffix = value.Payment_Due_By__c == null
            ? ''
            : String.valueOf(value.Payment_Due_By__c);
          notice.values.put('StudentName', value.Student__r.Name);
          notice.values.put('ProgrammeName', value.Programme__r.Name);
          notice.values.put('BranchOfStudy', value.Branch__r.Name);
          notice.values.put('AcademicYear', value.Academic_Year__c);
          notice.values.put(
            'RollNumber',
            value.Roll_Number__c == null ? '' : value.Roll_Number__c
          );
          notice.values.put(
            'PaymentDueBy',
            value.Payment_Due_By__c == null
              ? ''
              : value.Payment_Due_By__c.format()
          );
          notice.values.put(
            'BalanceDue',
            MessageService.money(money.get(value.Id).balance)
          );
          notice.values.put('Reason', reason == null ? '' : reason);
          notices.add(notice);
        }
      }
      MessageService.notify(eventKey, notices);
    } catch (Exception failure) {
      // Messages never block the admission transition.
      Logger.error('CollegeProvisionalService.notify', failure, null);
    }
  }

  private static Set<Id> idsOf(List<Programme_Enrolment__c> values) {
    return new Map<Id, Programme_Enrolment__c>(values).keySet();
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
