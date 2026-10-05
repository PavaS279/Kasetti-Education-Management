/**
 * Credit notes and refunds (F2.4).
 *
 * A credit note records money owed back to a payer. It is raised from an
 * overpayment, automatically when a transfer moves a learner to a cheaper class,
 * or by finance against a paid invoice (withdrawal, goodwill). Its balance is
 * used in two ways:
 *  - applied to the payer's open invoices, as a payment with method
 *    "Credit Note" so the existing allocation ledger stays the single source of
 *    truth for what an invoice has received (and, when Auto_Apply_Credit is on,
 *    automatically as each new invoice is issued);
 *  - refunded: a refund request up to Refund_Auto_Approve_Limit is approved at
 *    once; above it, a KEM_Approve_Refunds user other than the requester decides.
 *    Finance then records the payout reference.
 *
 * Ledger fields are system-managed, so writes run in system mode after the
 * KEM_Manage_Billing / KEM_Approve_Refunds checks in every public entry point.
 */
public with sharing class CreditService {
  public static final String APPROVE_PERMISSION = 'KEM_Approve_Refunds';
  public static final String CREDIT_METHOD = 'Credit Note';
  public static final Set<String> USABLE = new Set<String>{
    'Open',
    'Partially Used'
  };
  public static final Set<String> PENDING_REFUND = new Set<String>{
    'Requested',
    'Approved'
  };
  private static final Set<String> MANUAL_ORIGINS = new Set<String>{
    'Withdrawal',
    'Goodwill',
    'Other'
  };

  public class CreditRequest {
    @AuraEnabled
    public Id sourceInvoiceId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public String origin { get; set; }
    @AuraEnabled
    public String reason { get; set; }
  }

  public class RefundRequest {
    @AuraEnabled
    public Id creditNoteId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public String method { get; set; }
    @AuraEnabled
    public String reason { get; set; }
  }

  public class CreditView {
    @AuraEnabled
    public Credit_Note__c creditNote;
    @AuraEnabled
    public List<Student_Payment__c> applications;
    @AuraEnabled
    public List<Refund__c> refunds;
    @AuraEnabled
    public List<Student_Invoice__c> openInvoices;
    /** Balance not yet reserved by a pending refund. */
    @AuraEnabled
    public Decimal available;
    @AuraEnabled
    public Decimal reserved;
    @AuraEnabled
    public Decimal autoApproveLimit;
    @AuraEnabled
    public Boolean canManage;
    @AuraEnabled
    public Boolean canApprove;
    @AuraEnabled
    public Id currentUserId;
  }

  public class RefundQueue {
    @AuraEnabled
    public List<Refund__c> awaitingApproval;
    @AuraEnabled
    public List<Refund__c> awaitingPayout;
    @AuraEnabled
    public List<Credit_Note__c> openCredits;
    @AuraEnabled
    public Decimal openCreditTotal = 0;
    @AuraEnabled
    public Boolean canManage;
    @AuraEnabled
    public Boolean canApprove;
    @AuraEnabled
    public Id currentUserId;
  }

  // ---------------------------------------------------------- credit notes

  /** Credits part of what was paid on an invoice (withdrawal, goodwill, other). */
  public static Id issueForInvoice(CreditRequest request) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    if (request == null || request.sourceInvoiceId == null) {
      throw new AppException('Choose the invoice to credit.');
    }
    if (request.amount == null || request.amount <= 0) {
      throw new AppException('Enter a credit amount greater than zero.');
    }
    if (String.isBlank(request.reason)) {
      throw new AppException('Enter a reason for the credit note.');
    }
    String origin = String.isBlank(request.origin)
      ? 'Goodwill'
      : request.origin;
    if (!MANUAL_ORIGINS.contains(origin)) {
      throw new AppException('Choose Withdrawal, Goodwill or Other.');
    }
    Student_Invoice__c invoice = [
      SELECT
        Id,
        Name,
        Status__c,
        Amount_Paid__c,
        Bill_To__c,
        Learner__c,
        Learner_Account__c,
        Enrolment__c,
        Branch__c
      FROM Student_Invoice__c
      WHERE Id = :request.sourceInvoiceId
      WITH SYSTEM_MODE
    ];
    if (
      !(invoice.Status__c == 'Paid' ||
      invoice.Status__c == 'Partially Paid')
    ) {
      throw new AppException(
        'Only money already paid can be credited. Cancel an unpaid invoice instead.'
      );
    }
    Decimal alreadyCredited = nvl(
      (Decimal) [
          SELECT SUM(Amount__c) total
          FROM Credit_Note__c
          WHERE Source_Invoice__c = :invoice.Id AND Status__c != 'Void'
          WITH SYSTEM_MODE
        ][0]
        .get('total')
    );
    Decimal creditable = nvl(invoice.Amount_Paid__c) - alreadyCredited;
    if (request.amount > creditable) {
      throw new AppException(
        'At most ' +
          creditable.setScale(2) +
          ' can be credited on ' +
          invoice.Name +
          ' (paid ' +
          nvl(invoice.Amount_Paid__c).setScale(2) +
          ', already credited ' +
          alreadyCredited.setScale(2) +
          ').'
      );
    }
    Credit_Note__c note = new Credit_Note__c(
      Bill_To__c = invoice.Bill_To__c,
      Learner__c = invoice.Learner__c,
      Learner_Account__c = invoice.Learner_Account__c,
      Enrolment__c = invoice.Enrolment__c,
      Source_Invoice__c = invoice.Id,
      Branch__c = invoice.Branch__c,
      Origin__c = origin,
      Reason__c = request.reason.left(255)
    );
    return insertNote(note, request.amount);
  }

  /**
   * Closes an overpayment exception by holding the unallocated amount as a
   * credit note for the payer.
   */
  public static Id holdOverpayment(Id paymentId) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    Student_Payment__c payment = [
      SELECT
        Id,
        Name,
        Status__c,
        Reconciliation_Status__c,
        Unallocated_Amount__c,
        Payer__c,
        Learner__c,
        Branch__c,
        Student_Invoice__c,
        Student_Invoice__r.Learner_Account__c,
        Student_Invoice__r.Enrolment__c
      FROM Student_Payment__c
      WHERE Id = :paymentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (
      payment.Status__c != 'Confirmed' ||
      payment.Reconciliation_Status__c != 'Exception' ||
      nvl(payment.Unallocated_Amount__c) <= 0
    ) {
      throw new AppException(
        'Only a confirmed payment with an unallocated amount can be held as credit.'
      );
    }
    Credit_Note__c note = new Credit_Note__c(
      Bill_To__c = payment.Payer__c,
      Learner__c = payment.Learner__c,
      Learner_Account__c = payment.Student_Invoice__r?.Learner_Account__c,
      Enrolment__c = payment.Student_Invoice__r?.Enrolment__c,
      Source_Payment__c = payment.Id,
      Branch__c = payment.Branch__c,
      Origin__c = 'Overpayment',
      Reason__c = ('Overpayment on ' + payment.Name).left(255)
    );
    Id noteId = insertNote(note, payment.Unallocated_Amount__c);
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Student_Payment__c(
            Id = payment.Id,
            Reconciliation_Status__c = 'Reconciled',
            Reconciliation_Note__c = (payment.Unallocated_Amount__c.setScale(
                2
              ) +
              ' held as credit note ' +
              noteName(noteId) +
              '.')
              .left(255),
            Reconciled_On__c = System.now(),
            Reconciled_By__c = UserInfo.getUserId()
          )
        }
      );
    return noteId;
  }

  /**
   * Credit for a transfer to a cheaper class after the original enrolment was
   * invoiced. Authorised by the transfer itself (edit access to the enrolment).
   */
  public static Id issueForTransfer(
    Id newEnrolmentId,
    Id oldEnrolmentId,
    Decimal amount,
    String reason
  ) {
    if (amount == null || amount <= 0) {
      return null;
    }
    CourseOfferingParticipant enrolment = [
      SELECT Id, ParticipantContactId, ParticipantAccountId, Branch__c
      FROM CourseOfferingParticipant
      WHERE Id = :newEnrolmentId
      WITH SYSTEM_MODE
    ];
    Id sourceInvoiceId;
    for (Student_Invoice__c invoice : [
      SELECT Id
      FROM Student_Invoice__c
      WHERE Enrolment__c = :oldEnrolmentId AND Status__c != 'Cancelled'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ]) {
      sourceInvoiceId = invoice.Id;
    }
    return insertNote(
      new Credit_Note__c(
        Bill_To__c = BillingService.billToFor(enrolment.ParticipantContactId),
        Learner__c = enrolment.ParticipantContactId,
        Learner_Account__c = enrolment.ParticipantAccountId,
        Enrolment__c = enrolment.Id,
        Source_Invoice__c = sourceInvoiceId,
        Branch__c = enrolment.Branch__c,
        Origin__c = 'Transfer',
        Reason__c = reason == null ? null : reason.left(255)
      ),
      amount
    );
  }

  /** Voids a credit note that has not been used or refunded. */
  public static void voidNote(Id creditNoteId, String reason) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for voiding the credit note.');
    }
    Credit_Note__c note = loadNote(creditNoteId, true);
    if (
      note.Status__c != 'Open' ||
      nvl(note.Amount_Applied__c) > 0 ||
      nvl(note.Amount_Refunded__c) > 0 ||
      reserved(note.Id) > 0
    ) {
      throw new AppException(
        'Only an unused credit note without pending refunds can be voided.'
      );
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Credit_Note__c(
            Id = note.Id,
            Status__c = 'Void',
            Void_Reason__c = reason.left(255)
          )
        }
      );
  }

  // ------------------------------------------------------- applying credit

  /** Applies credit to one open invoice of the same payer; null amount uses as much as possible. */
  public static Decimal apply(Id creditNoteId, Id invoiceId, Decimal amount) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    if (amount != null && amount <= 0) {
      throw new AppException('Enter an amount greater than zero.');
    }
    Credit_Note__c note = loadNote(creditNoteId, true);
    Student_Invoice__c invoice = loadOpenInvoice(invoiceId);
    if (invoice.Bill_To__c != note.Bill_To__c) {
      throw new AppException(
        'The invoice is billed to a different payer than the credit note.'
      );
    }
    Decimal available = available(note);
    if (!USABLE.contains(note.Status__c) || available <= 0) {
      throw new AppException('This credit note has no balance to use.');
    }
    if (amount != null && amount > available) {
      throw new AppException(
        'Only ' + available.setScale(2) + ' of this credit is available.'
      );
    }
    Decimal used = applyTo(
      note,
      invoice,
      nvl(invoice.Total__c) - nvl(invoice.Amount_Paid__c),
      amount == null ? available : amount
    );
    if (used <= 0) {
      throw new AppException('The invoice has nothing left to pay.');
    }
    BillingService.refreshInvoices(new Set<Id>{ invoice.Id });
    return used;
  }

  /**
   * Applies the payers' open credit to newly issued invoices, oldest credit
   * first. Runs as part of issuing (manual or recurring billing).
   */
  public static void autoApply(Set<Id> invoiceIds) {
    if (
      invoiceIds == null ||
      invoiceIds.isEmpty() ||
      !AppSettings.getBoolean('Auto_Apply_Credit', true)
    ) {
      return;
    }
    List<Student_Invoice__c> invoices = [
      SELECT Id, Bill_To__c, Learner__c, Branch__c, Total__c, Amount_Paid__c
      FROM Student_Invoice__c
      WHERE Id IN :invoiceIds AND Status__c IN :BillingService.OPEN_STATUSES
      WITH SYSTEM_MODE
    ];
    Set<Id> payers = new Set<Id>();
    for (Student_Invoice__c invoice : invoices) {
      payers.add(invoice.Bill_To__c);
    }
    payers.remove(null);
    if (payers.isEmpty()) {
      return;
    }
    Map<Id, List<Credit_Note__c>> creditsByPayer = new Map<Id, List<Credit_Note__c>>();
    for (Credit_Note__c note : [
      SELECT
        Id,
        Name,
        Bill_To__c,
        Amount__c,
        Amount_Applied__c,
        Amount_Refunded__c,
        Balance__c,
        Status__c
      FROM Credit_Note__c
      WHERE Bill_To__c IN :payers AND Status__c IN :USABLE AND Balance__c > 0
      WITH SYSTEM_MODE
      ORDER BY Issue_Date__c, Name
    ]) {
      if (!creditsByPayer.containsKey(note.Bill_To__c)) {
        creditsByPayer.put(note.Bill_To__c, new List<Credit_Note__c>());
      }
      creditsByPayer.get(note.Bill_To__c).add(note);
    }
    if (creditsByPayer.isEmpty()) {
      return;
    }
    Set<Id> noteIds = new Set<Id>();
    for (List<Credit_Note__c> notes : creditsByPayer.values()) {
      for (Credit_Note__c note : notes) {
        noteIds.add(note.Id);
      }
    }
    Map<Id, Decimal> reservedByNote = reservedFor(noteIds);
    // Formula and roll-up fields cannot be assigned, so track what is left here.
    Map<Id, Decimal> free = new Map<Id, Decimal>();
    for (List<Credit_Note__c> notes : creditsByPayer.values()) {
      for (Credit_Note__c note : notes) {
        free.put(
          note.Id,
          nvl(note.Balance__c) - nvl(reservedByNote.get(note.Id))
        );
      }
    }
    Set<Id> touched = new Set<Id>();
    for (Student_Invoice__c invoice : invoices) {
      List<Credit_Note__c> credits = creditsByPayer.get(invoice.Bill_To__c);
      if (credits == null) {
        continue;
      }
      Decimal due = nvl(invoice.Total__c) - nvl(invoice.Amount_Paid__c);
      for (Credit_Note__c note : credits) {
        if (free.get(note.Id) <= 0 || due <= 0) {
          continue;
        }
        Decimal used = applyTo(note, invoice, due, free.get(note.Id));
        if (used > 0) {
          touched.add(invoice.Id);
          free.put(note.Id, free.get(note.Id) - used);
          due -= used;
        }
      }
    }
    BillingService.refreshInvoices(touched);
  }

  /** Creates the credit payment and allocation; returns the amount used (0 when nothing is due). */
  private static Decimal applyTo(
    Credit_Note__c note,
    Student_Invoice__c invoice,
    Decimal due,
    Decimal amount
  ) {
    Decimal used = Math.min(due, amount).setScale(2);
    if (used <= 0) {
      return 0;
    }
    Writer writer = new Writer();
    Student_Payment__c payment = new Student_Payment__c(
      Payer__c = note.Bill_To__c,
      Learner__c = invoice.Learner__c,
      Student_Invoice__c = invoice.Id,
      Branch__c = invoice.Branch__c,
      Credit_Note__c = note.Id,
      Amount__c = used,
      Method__c = CREDIT_METHOD,
      Reference__c = note.Name,
      Payment_Date__c = Date.today(),
      Status__c = 'Confirmed',
      Reconciliation_Status__c = 'Reconciled',
      Reconciliation_Note__c = ('Paid from credit note ' + note.Name).left(255),
      Reconciled_On__c = System.now(),
      Reconciled_By__c = UserInfo.getUserId()
    );
    writer.insertRecords(new List<SObject>{ payment });
    writer.insertRecords(
      new List<SObject>{
        new Payment_Allocation__c(
          Student_Invoice__c = invoice.Id,
          Student_Payment__c = payment.Id,
          Amount__c = used,
          Allocated_On__c = System.now()
        )
      }
    );
    Decimal applied = nvl(note.Amount_Applied__c) + used;
    note.Amount_Applied__c = applied;
    writer.updateRecords(
      new List<SObject>{
        new Credit_Note__c(
          Id = note.Id,
          Amount_Applied__c = applied,
          Status__c = statusFor(
            note.Amount__c,
            applied,
            nvl(note.Amount_Refunded__c)
          )
        )
      }
    );
    note.Status__c = statusFor(
      note.Amount__c,
      applied,
      nvl(note.Amount_Refunded__c)
    );
    return used;
  }

  // --------------------------------------------------------------- refunds

  /** Requests a payout of credit; within the auto-approval limit it is approved at once. */
  public static Id requestRefund(RefundRequest request) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    if (request == null || request.creditNoteId == null) {
      throw new AppException('Choose the credit note to refund.');
    }
    if (request.amount == null || request.amount <= 0) {
      throw new AppException('Enter a refund amount greater than zero.');
    }
    if (String.isBlank(request.method)) {
      throw new AppException('Choose how the refund will be paid.');
    }
    if (String.isBlank(request.reason)) {
      throw new AppException('Enter a reason for the refund.');
    }
    Credit_Note__c note = loadNote(request.creditNoteId, true);
    Decimal available = USABLE.contains(note.Status__c) ? available(note) : 0;
    if (request.amount > available) {
      throw new AppException(
        'Only ' +
          available.setScale(2) +
          ' of this credit can be refunded (pending refunds included).'
      );
    }
    Boolean auto = request.amount <= autoApproveLimit();
    Refund__c refund = new Refund__c(
      Credit_Note__c = note.Id,
      Payee__c = note.Bill_To__c,
      Branch__c = note.Branch__c,
      Amount__c = request.amount.setScale(2),
      Method__c = request.method,
      Reason__c = request.reason.left(255),
      Requested_By__c = UserInfo.getUserId(),
      Status__c = auto ? 'Approved' : 'Requested',
      Auto_Approved__c = auto,
      Decided_On__c = auto ? System.now() : null
    );
    new Writer().insertRecords(new List<SObject>{ refund });
    return refund.Id;
  }

  public static void approveRefund(Id refundId) {
    decide(refundId, true, null);
  }

  public static void rejectRefund(Id refundId, String reason) {
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for rejecting the refund.');
    }
    decide(refundId, false, reason);
  }

  private static void decide(Id refundId, Boolean approve, String reason) {
    RecordAccess.assertPermission(APPROVE_PERMISSION);
    Refund__c refund = loadRefund(refundId);
    Set<String> decidable = approve
      ? new Set<String>{ 'Requested' }
      : PENDING_REFUND;
    if (!decidable.contains(refund.Status__c)) {
      throw new AppException(
        approve
          ? 'Only requested refunds can be approved.'
          : 'Only refunds that have not been paid can be rejected.'
      );
    }
    if (refund.Requested_By__c == UserInfo.getUserId()) {
      throw new AppException(
        'A refund must be decided by someone other than the person who requested it.'
      );
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Refund__c(
            Id = refund.Id,
            Status__c = approve ? 'Approved' : 'Rejected',
            Approved_By__c = UserInfo.getUserId(),
            Decided_On__c = System.now(),
            Rejection_Reason__c = reason == null ? null : reason.left(255)
          )
        }
      );
  }

  /** Records the payout of an approved refund and reduces the credit balance. */
  public static void markRefundPaid(
    Id refundId,
    String reference,
    Date paidOn
  ) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    if (String.isBlank(reference)) {
      throw new AppException(
        'Enter the payout reference (bank or UPI transaction, cheque number).'
      );
    }
    Refund__c refund = loadRefund(refundId);
    if (refund.Status__c != 'Approved') {
      throw new AppException('Only approved refunds can be paid out.');
    }
    Credit_Note__c note = loadNote(refund.Credit_Note__c, true);
    Decimal refunded = nvl(note.Amount_Refunded__c) + refund.Amount__c;
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Refund__c(
            Id = refund.Id,
            Status__c = 'Paid',
            Reference__c = reference.left(100),
            Paid_On__c = paidOn == null ? Date.today() : paidOn
          ),
          new Credit_Note__c(
            Id = note.Id,
            Amount_Refunded__c = refunded,
            Status__c = statusFor(
              note.Amount__c,
              nvl(note.Amount_Applied__c),
              refunded
            )
          )
        }
      );
  }

  // ----------------------------------------------------------------- reads

  public static CreditView getCreditNote(Id creditNoteId) {
    List<Credit_Note__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Origin__c,
        Reason__c,
        Issue_Date__c,
        Amount__c,
        Amount_Applied__c,
        Amount_Refunded__c,
        Balance__c,
        Void_Reason__c,
        Bill_To__c,
        Bill_To__r.Name,
        Bill_To__r.Email,
        Learner__r.Name,
        Learner_Account__c,
        Enrolment__c,
        Enrolment__r.CourseOffering.Name,
        Source_Invoice__c,
        Source_Invoice__r.Name,
        Source_Payment__c,
        Source_Payment__r.Name,
        Branch__r.Name
      FROM Credit_Note__c
      WHERE Id = :creditNoteId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Credit note not found or not accessible.');
    }
    CreditView view = new CreditView();
    view.creditNote = rows[0];
    view.applications = [
      SELECT
        Id,
        Name,
        Amount__c,
        Payment_Date__c,
        Student_Invoice__c,
        Student_Invoice__r.Name
      FROM Student_Payment__c
      WHERE Credit_Note__c = :creditNoteId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ];
    view.refunds = [
      SELECT
        Id,
        Name,
        Amount__c,
        Method__c,
        Status__c,
        Reason__c,
        Auto_Approved__c,
        Requested_By__c,
        Requested_By__r.Name,
        Approved_By__r.Name,
        Decided_On__c,
        Rejection_Reason__c,
        Paid_On__c,
        Reference__c,
        CreatedDate
      FROM Refund__c
      WHERE Credit_Note__c = :creditNoteId
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
    ];
    view.reserved = 0;
    for (Refund__c refund : view.refunds) {
      if (PENDING_REFUND.contains(refund.Status__c)) {
        view.reserved += refund.Amount__c;
      }
    }
    view.available = USABLE.contains(view.creditNote.Status__c)
      ? Math.max(0, nvl(view.creditNote.Balance__c) - view.reserved)
      : 0;
    view.openInvoices = [
      SELECT
        Id,
        Name,
        Due_Date__c,
        Balance_Due__c,
        Enrolment__r.CourseOffering.Name
      FROM Student_Invoice__c
      WHERE
        Bill_To__c = :view.creditNote.Bill_To__c
        AND Status__c IN :BillingService.OPEN_STATUSES
      WITH USER_MODE
      ORDER BY Due_Date__c
      LIMIT 50
    ];
    view.autoApproveLimit = autoApproveLimit();
    view.canManage = FeatureManagement.checkPermission(
      BillingService.MANAGE_PERMISSION
    );
    view.canApprove = FeatureManagement.checkPermission(APPROVE_PERMISSION);
    view.currentUserId = UserInfo.getUserId();
    return view;
  }

  /** Refund work queues and open credit for the Finance Desk (records visible to the user). */
  public static RefundQueue refundQueue() {
    RefundQueue queue = new RefundQueue();
    queue.awaitingApproval = refundList('Requested');
    queue.awaitingPayout = refundList('Approved');
    queue.openCredits = [
      SELECT
        Id,
        Name,
        Origin__c,
        Issue_Date__c,
        Balance__c,
        Bill_To__r.Name,
        Learner__r.Name
      FROM Credit_Note__c
      WHERE Status__c IN :USABLE AND Balance__c > 0
      WITH USER_MODE
      ORDER BY Issue_Date__c
      LIMIT 50
    ];
    queue.openCreditTotal = nvl(
      (Decimal) [
          SELECT SUM(Balance__c) total
          FROM Credit_Note__c
          WHERE Status__c IN :USABLE
          WITH USER_MODE
        ][0]
        .get('total')
    );
    queue.canManage = FeatureManagement.checkPermission(
      BillingService.MANAGE_PERMISSION
    );
    queue.canApprove = FeatureManagement.checkPermission(APPROVE_PERMISSION);
    queue.currentUserId = UserInfo.getUserId();
    return queue;
  }

  /** Credit notes of a learner visible to the running user, newest first. */
  public static List<Credit_Note__c> learnerCredits(Id learnerAccountId) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Origin__c,
        Issue_Date__c,
        Amount__c,
        Balance__c,
        Bill_To__r.Name
      FROM Credit_Note__c
      WHERE Learner_Account__c = :learnerAccountId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 100
    ];
  }

  private static List<Refund__c> refundList(String status) {
    return [
      SELECT
        Id,
        Name,
        Amount__c,
        Method__c,
        Status__c,
        Reason__c,
        Auto_Approved__c,
        CreatedDate,
        Requested_By__c,
        Requested_By__r.Name,
        Payee__r.Name,
        Credit_Note__c,
        Credit_Note__r.Name
      FROM Refund__c
      WHERE Status__c = :status
      WITH USER_MODE
      ORDER BY CreatedDate
      LIMIT 50
    ];
  }

  // --------------------------------------------------------------- helpers

  public static Decimal autoApproveLimit() {
    return AppSettings.getDecimal('Refund_Auto_Approve_Limit', 0);
  }

  @TestVisible
  private static String statusFor(
    Decimal amount,
    Decimal applied,
    Decimal refunded
  ) {
    Decimal used = nvl(applied) + nvl(refunded);
    return used >= nvl(amount) ? 'Used' : used > 0 ? 'Partially Used' : 'Open';
  }

  private static Id insertNote(Credit_Note__c note, Decimal amount) {
    note.Amount__c = amount.setScale(2);
    note.Amount_Applied__c = 0;
    note.Amount_Refunded__c = 0;
    note.Status__c = 'Open';
    note.Issue_Date__c = Date.today();
    new Writer().insertRecords(new List<SObject>{ note });
    return note.Id;
  }

  private static String noteName(Id noteId) {
    return [SELECT Name FROM Credit_Note__c WHERE Id = :noteId WITH SYSTEM_MODE]
    .Name;
  }

  private static Decimal available(Credit_Note__c note) {
    return Math.max(0, nvl(note.Balance__c) - reserved(note.Id));
  }

  private static Decimal reserved(Id noteId) {
    return nvl(reservedFor(new Set<Id>{ noteId }).get(noteId));
  }

  private static Map<Id, Decimal> reservedFor(Set<Id> noteIds) {
    Map<Id, Decimal> reserved = new Map<Id, Decimal>();
    for (AggregateResult row : [
      SELECT Credit_Note__c note, SUM(Amount__c) total
      FROM Refund__c
      WHERE Credit_Note__c IN :noteIds AND Status__c IN :PENDING_REFUND
      WITH SYSTEM_MODE
      GROUP BY Credit_Note__c
    ]) {
      reserved.put((Id) row.get('note'), (Decimal) row.get('total'));
    }
    return reserved;
  }

  private static Credit_Note__c loadNote(Id noteId, Boolean lock) {
    List<Credit_Note__c> rows = lock
      ? [
          SELECT
            Id,
            Name,
            Status__c,
            Bill_To__c,
            Branch__c,
            Amount__c,
            Amount_Applied__c,
            Amount_Refunded__c,
            Balance__c
          FROM Credit_Note__c
          WHERE Id = :noteId
          WITH SYSTEM_MODE
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Name,
            Status__c,
            Bill_To__c,
            Branch__c,
            Amount__c,
            Amount_Applied__c,
            Amount_Refunded__c,
            Balance__c
          FROM Credit_Note__c
          WHERE Id = :noteId
          WITH SYSTEM_MODE
        ];
    if (rows.isEmpty()) {
      throw new AppException('Credit note not found.');
    }
    return rows[0];
  }

  private static Student_Invoice__c loadOpenInvoice(Id invoiceId) {
    List<Student_Invoice__c> rows = [
      SELECT
        Id,
        Status__c,
        Bill_To__c,
        Learner__c,
        Branch__c,
        Total__c,
        Amount_Paid__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Invoice not found.');
    }
    if (!BillingService.OPEN_STATUSES.contains(rows[0].Status__c)) {
      throw new AppException(
        'Credit can only be used on an issued invoice with a balance.'
      );
    }
    return rows[0];
  }

  private static Refund__c loadRefund(Id refundId) {
    List<Refund__c> rows = [
      SELECT Id, Status__c, Amount__c, Credit_Note__c, Requested_By__c
      FROM Refund__c
      WHERE Id = :refundId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Refund not found.');
    }
    return rows[0];
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** Ledger writes, authorised by the permission checks in the public entry points. */
  private without sharing class Writer {
    void insertRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
      }
    }

    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
