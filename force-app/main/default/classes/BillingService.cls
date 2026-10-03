/**
 * Billing ledger (ADR-002): invoices from agreed enrolment prices, payments,
 * allocation to invoices oldest-due-first, and reconciliation.
 *
 * Every write requires the KEM_Manage_Billing custom permission and runs in
 * system mode after that check, because all ledger fields are system-managed
 * (read-only to users) so that totals can only change through this service.
 * Reads that drive the UI run in user mode so record visibility is respected.
 */
public with sharing class BillingService {
  public static final String MANAGE_PERMISSION = 'KEM_Manage_Billing';
  public static final Set<String> OPEN_STATUSES = new Set<String>{
    'Issued',
    'Partially Paid'
  };
  public static final Set<String> BILLABLE_ENROLMENT_STATUSES = new Set<String>{
    'Enrolled',
    'On Hold',
    'Completed'
  };

  public class PaymentRequest {
    @AuraEnabled
    public Id invoiceId { get; set; }
    @AuraEnabled
    public Id payerContactId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public String method { get; set; }
    @AuraEnabled
    public String reference { get; set; }
    @AuraEnabled
    public String gatewayTransactionId { get; set; }
    @AuraEnabled
    public Date paymentDate { get; set; }
    /** False records the payment as Pending (for example a cheque awaiting clearance). */
    @AuraEnabled
    public Boolean confirmed { get; set; }
  }

  public class PaymentResult {
    @AuraEnabled
    public Id paymentId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String reconciliationStatus;
    @AuraEnabled
    public String receiptNumber;
    @AuraEnabled
    public Decimal allocated;
    @AuraEnabled
    public Decimal unallocated;
    /** True when the gateway transaction was already recorded (idempotent replay). */
    @AuraEnabled
    public Boolean duplicate = false;
  }

  public class InvoiceView {
    @AuraEnabled
    public Student_Invoice__c invoice;
    @AuraEnabled
    public List<Invoice_Line__c> lines;
    @AuraEnabled
    public List<Payment_Allocation__c> allocations;
    @AuraEnabled
    public List<Student_Payment__c> pendingPayments;
    @AuraEnabled
    public Boolean canManage;
  }

  public class FinanceDesk {
    @AuraEnabled
    public Decimal outstanding = 0;
    @AuraEnabled
    public Decimal overdueAmount = 0;
    @AuraEnabled
    public Integer overdueCount = 0;
    @AuraEnabled
    public Decimal collectedThisMonth = 0;
    @AuraEnabled
    public List<Student_Invoice__c> overdue;
    @AuraEnabled
    public List<Student_Payment__c> pending;
    @AuraEnabled
    public List<Student_Payment__c> exceptions;
    @AuraEnabled
    public List<Student_Payment__c> recent;
    @AuraEnabled
    public Boolean canManage;
  }

  // ------------------------------------------------------------- invoices

  /** Raises an invoice for the enrolment's uninvoiced fee lines; issues it when issueNow is true. */
  public static Id createInvoice(Id enrolmentId, Boolean issueNow) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    CourseOfferingParticipant enrolment = loadEnrolment(enrolmentId);
    if (!BILLABLE_ENROLMENT_STATUSES.contains(enrolment.ParticipationStatus)) {
      throw new AppException(
        'Only active or completed enrolments can be invoiced.'
      );
    }
    if (enrolment.Discount_Approval_Status__c == 'Pending') {
      throw new AppException(
        'The discount on this enrolment is waiting for approval. Approve or reject it before invoicing.'
      );
    }
    List<Enrolment_Fee_Line__c> feeLines = [
      SELECT
        Id,
        Fee_Type__c,
        Description__c,
        Unit_Amount__c,
        Discount_Amount__c,
        Tax_Amount__c,
        Line_Total__c
      FROM Enrolment_Fee_Line__c
      WHERE Enrolment__c = :enrolmentId AND Invoiced__c = FALSE
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (feeLines.isEmpty()) {
      throw new AppException(
        'There is nothing left to invoice on this enrolment.'
      );
    }
    BranchPolicy policy = new BranchPolicy(loadBranch(enrolment.Branch__c));
    Student_Invoice__c invoice = new Student_Invoice__c(
      Name = 'DRAFT',
      Enrolment__c = enrolmentId,
      Learner__c = enrolment.ParticipantContactId,
      Learner_Account__c = enrolment.ParticipantContact.AccountId,
      Bill_To__c = billToFor(enrolment.ParticipantContactId),
      Branch__c = enrolment.Branch__c,
      Status__c = 'Draft'
    );
    if (issueNow == true) {
      stampIssue(invoice, policy);
    }
    Writer writer = new Writer();
    writer.insertRecords(new List<SObject>{ invoice });
    Student_Invoice__c numbered = [
      SELECT Sequence__c
      FROM Student_Invoice__c
      WHERE Id = :invoice.Id
      WITH SYSTEM_MODE
    ];
    List<SObject> updates = new List<SObject>{
      new Student_Invoice__c(
        Id = invoice.Id,
        Name = policy.invoicePrefix() + '-' + numbered.Sequence__c
      )
    };
    List<Invoice_Line__c> lines = new List<Invoice_Line__c>();
    for (Enrolment_Fee_Line__c feeLine : feeLines) {
      lines.add(
        new Invoice_Line__c(
          Student_Invoice__c = invoice.Id,
          Enrolment_Fee_Line__c = feeLine.Id,
          Fee_Type__c = feeLine.Fee_Type__c,
          Description__c = feeLine.Description__c,
          Unit_Amount__c = feeLine.Unit_Amount__c,
          Discount_Amount__c = feeLine.Discount_Amount__c,
          Tax_Amount__c = feeLine.Tax_Amount__c,
          Line_Total__c = feeLine.Line_Total__c
        )
      );
      updates.add(
        new Enrolment_Fee_Line__c(Id = feeLine.Id, Invoiced__c = true)
      );
    }
    writer.insertRecords(lines);
    writer.updateRecords(updates);
    refreshInvoices(new Set<Id>{ invoice.Id });
    return invoice.Id;
  }

  public static void issue(Id invoiceId) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Invoice__c invoice = loadInvoice(invoiceId);
    if (invoice.Status__c != 'Draft') {
      throw new AppException('Only draft invoices can be issued.');
    }
    Student_Invoice__c change = new Student_Invoice__c(Id = invoiceId);
    stampIssue(change, new BranchPolicy(loadBranch(invoice.Branch__c)));
    new Writer().updateRecords(new List<SObject>{ change });
    refreshInvoices(new Set<Id>{ invoiceId });
  }

  /** Cancels an unpaid invoice and releases its fee lines so they can be invoiced again. */
  public static void cancel(Id invoiceId, String reason) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for cancelling the invoice.');
    }
    Student_Invoice__c invoice = loadInvoice(invoiceId);
    if (!(invoice.Status__c == 'Draft' || invoice.Status__c == 'Issued')) {
      throw new AppException(
        'Only draft or unpaid issued invoices can be cancelled.'
      );
    }
    if (invoice.Amount_Paid__c != null && invoice.Amount_Paid__c > 0) {
      throw new AppException(
        'Payments are allocated to this invoice; it cannot be cancelled.'
      );
    }
    List<SObject> updates = new List<SObject>{
      new Student_Invoice__c(
        Id = invoiceId,
        Status__c = 'Cancelled',
        Cancellation_Reason__c = reason.left(255)
      )
    };
    for (Invoice_Line__c line : [
      SELECT Enrolment_Fee_Line__c
      FROM Invoice_Line__c
      WHERE Student_Invoice__c = :invoiceId AND Enrolment_Fee_Line__c != NULL
      WITH SYSTEM_MODE
    ]) {
      updates.add(
        new Enrolment_Fee_Line__c(
          Id = line.Enrolment_Fee_Line__c,
          Invoiced__c = false
        )
      );
    }
    new Writer().updateRecords(updates);
    refreshEnrolments(new Set<Id>{ invoice.Enrolment__c });
  }

  // ------------------------------------------------------------- payments

  /** Records a payment. Replaying a known gateway transaction returns the original payment. */
  public static PaymentResult recordPayment(PaymentRequest request) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    if (request == null || request.amount == null || request.amount <= 0) {
      throw new AppException('Enter a payment amount greater than zero.');
    }
    if (String.isBlank(request.method)) {
      throw new AppException('Select a payment method.');
    }
    if (String.isNotBlank(request.gatewayTransactionId)) {
      List<Student_Payment__c> existing = [
        SELECT Id
        FROM Student_Payment__c
        WHERE Gateway_Transaction_Id__c = :request.gatewayTransactionId
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!existing.isEmpty()) {
        PaymentResult replay = result(existing[0].Id);
        replay.duplicate = true;
        return replay;
      }
    }
    Student_Invoice__c invoice;
    if (request.invoiceId != null) {
      invoice = loadInvoice(request.invoiceId);
      if (invoice.Status__c == 'Draft' || invoice.Status__c == 'Cancelled') {
        throw new AppException(
          'Payments can only be taken against issued invoices.'
        );
      }
    }
    Id payerId = request.payerContactId != null
      ? request.payerContactId
      : invoice?.Bill_To__c;
    if (payerId == null) {
      throw new AppException('Select the invoice or the payer.');
    }
    Boolean confirmed = request.confirmed != false;
    Student_Payment__c payment = new Student_Payment__c(
      Payer__c = payerId,
      Learner__c = invoice?.Learner__c,
      Student_Invoice__c = invoice?.Id,
      Branch__c = invoice?.Branch__c,
      Amount__c = request.amount.setScale(2),
      Method__c = request.method,
      Reference__c = String.isBlank(request.reference)
        ? null
        : request.reference.left(100),
      Gateway_Transaction_Id__c = String.isBlank(request.gatewayTransactionId)
        ? null
        : request.gatewayTransactionId,
      Payment_Date__c = request.paymentDate == null
        ? Date.today()
        : request.paymentDate,
      Status__c = 'Pending',
      Reconciliation_Status__c = 'Unreconciled'
    );
    try {
      new Writer().insertRecords(new List<SObject>{ payment });
    } catch (DmlException e) {
      // A concurrent notification for the same transaction won the race.
      if (
        e.getDmlType(0) == StatusCode.DUPLICATE_VALUE &&
        String.isNotBlank(request.gatewayTransactionId)
      ) {
        PaymentResult replay = result(
          [
            SELECT Id
            FROM Student_Payment__c
            WHERE Gateway_Transaction_Id__c = :request.gatewayTransactionId
            WITH SYSTEM_MODE
          ]
          .Id
        );
        replay.duplicate = true;
        return replay;
      }
      throw e;
    }
    if (confirmed) {
      return confirmPayment(payment.Id);
    }
    return result(payment.Id);
  }

  /** Confirms a pending payment, issues the receipt number, and allocates it. */
  public static PaymentResult confirmPayment(Id paymentId) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Payment__c payment = loadPayment(paymentId, true);
    if (payment.Status__c != 'Pending') {
      throw new AppException('Only pending payments can be confirmed.');
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Student_Payment__c(
            Id = paymentId,
            Status__c = 'Confirmed',
            Receipt_Number__c = 'RCT-' + payment.Name.substringAfter('-')
          )
        }
      );
    allocate(paymentId);
    return result(paymentId);
  }

  public static void failPayment(Id paymentId, String reason) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Payment__c payment = loadPayment(paymentId, true);
    if (payment.Status__c != 'Pending') {
      throw new AppException('Only pending payments can be marked as failed.');
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Student_Payment__c(
            Id = paymentId,
            Status__c = 'Failed',
            Reconciliation_Status__c = 'Reconciled',
            Reconciliation_Note__c = String.isBlank(reason)
              ? 'Payment failed.'
              : reason.left(255),
            Reconciled_On__c = System.now(),
            Reconciled_By__c = UserInfo.getUserId()
          )
        }
      );
  }

  /**
   * Retries allocation of an exception payment (for example after a new invoice
   * was raised). Anything still unallocated needs a note (refund, credit) to close.
   */
  public static PaymentResult resolveException(Id paymentId, String note) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Payment__c payment = loadPayment(paymentId, true);
    if (payment.Reconciliation_Status__c != 'Exception') {
      throw new AppException('This payment has no reconciliation exception.');
    }
    allocate(paymentId);
    PaymentResult outcome = result(paymentId);
    if (outcome.reconciliationStatus == 'Exception') {
      if (String.isBlank(note)) {
        throw new AppException(
          outcome.unallocated.setScale(2) +
          ' is still unallocated. Record how it was settled (refund or credit) to close the exception.'
        );
      }
      new Writer()
        .updateRecords(
          new List<SObject>{
            new Student_Payment__c(
              Id = paymentId,
              Reconciliation_Status__c = 'Reconciled',
              Reconciliation_Note__c = note.left(255),
              Reconciled_On__c = System.now(),
              Reconciled_By__c = UserInfo.getUserId()
            )
          }
        );
      outcome = result(paymentId);
    }
    return outcome;
  }

  /**
   * Allocates the unallocated amount of a confirmed payment: first to the invoice
   * it was made for, then to the payer's other open invoices, oldest due first.
   * Fully allocated payments are reconciled; a remainder raises an exception.
   */
  @TestVisible
  private static void allocate(Id paymentId) {
    Student_Payment__c payment = loadPayment(paymentId, true);
    Decimal remaining = payment.Amount__c - nvl(payment.Allocated_Amount__c);
    List<Student_Invoice__c> open = [
      SELECT Id, Name, Total__c, Amount_Paid__c, Due_Date__c, Enrolment__c
      FROM Student_Invoice__c
      WHERE
        Status__c IN :OPEN_STATUSES
        AND (Id = :payment.Student_Invoice__c
        OR Bill_To__c = :payment.Payer__c)
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    List<Student_Invoice__c> ordered = new List<Student_Invoice__c>();
    for (Student_Invoice__c invoice : open) {
      if (invoice.Id == payment.Student_Invoice__c) {
        ordered.add(invoice);
      }
    }
    for (Student_Invoice__c invoice : oldestDueFirst(open)) {
      if (invoice.Id != payment.Student_Invoice__c) {
        ordered.add(invoice);
      }
    }
    List<Payment_Allocation__c> allocations = new List<Payment_Allocation__c>();
    Set<Id> touched = new Set<Id>();
    for (Student_Invoice__c invoice : ordered) {
      if (remaining <= 0) {
        break;
      }
      Decimal balance = nvl(invoice.Total__c) - nvl(invoice.Amount_Paid__c);
      if (balance <= 0) {
        continue;
      }
      Decimal amount = Math.min(balance, remaining);
      allocations.add(
        new Payment_Allocation__c(
          Student_Invoice__c = invoice.Id,
          Student_Payment__c = paymentId,
          Amount__c = amount,
          Allocated_On__c = System.now()
        )
      );
      touched.add(invoice.Id);
      remaining -= amount;
    }
    Writer writer = new Writer();
    writer.insertRecords(allocations);
    refreshInvoices(touched);
    Student_Payment__c change = new Student_Payment__c(Id = paymentId);
    if (remaining <= 0) {
      change.Reconciliation_Status__c = 'Reconciled';
      change.Reconciled_On__c = System.now();
      change.Reconciled_By__c = UserInfo.getUserId();
    } else {
      change.Reconciliation_Status__c = 'Exception';
      change.Reconciliation_Note__c =
        remaining.setScale(2) +
        ' could not be allocated: the payer has no other open invoice (overpayment).';
    }
    writer.updateRecords(new List<SObject>{ change });
  }

  // ----------------------------------------------------------------- reads

  public static InvoiceView getInvoice(Id invoiceId) {
    InvoiceView view = new InvoiceView();
    List<Student_Invoice__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Issue_Date__c,
        Due_Date__c,
        Subtotal__c,
        Discount_Total__c,
        Tax_Total__c,
        Total__c,
        Amount_Paid__c,
        Balance_Due__c,
        Overdue__c,
        Cancellation_Reason__c,
        Notes__c,
        Bill_To__c,
        Bill_To__r.Name,
        Bill_To__r.Email,
        Learner__c,
        Learner__r.Name,
        Learner_Account__c,
        Enrolment__c,
        Enrolment__r.CourseOffering.Name,
        Branch__c,
        Branch__r.Name
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Invoice not found or not accessible.');
    }
    view.invoice = rows[0];
    view.lines = [
      SELECT
        Id,
        Fee_Type__c,
        Description__c,
        Unit_Amount__c,
        Discount_Amount__c,
        Tax_Amount__c,
        Line_Total__c
      FROM Invoice_Line__c
      WHERE Student_Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
    view.allocations = [
      SELECT
        Id,
        Amount__c,
        Allocated_On__c,
        Student_Payment__c,
        Student_Payment__r.Name,
        Student_Payment__r.Method__c,
        Student_Payment__r.Payment_Date__c,
        Student_Payment__r.Reference__c,
        Student_Payment__r.Receipt_Number__c
      FROM Payment_Allocation__c
      WHERE Student_Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Allocated_On__c
    ];
    view.pendingPayments = [
      SELECT Id, Name, Amount__c, Method__c, Payment_Date__c, Reference__c
      FROM Student_Payment__c
      WHERE Student_Invoice__c = :invoiceId AND Status__c = 'Pending'
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
    view.canManage = FeatureManagement.checkPermission(MANAGE_PERMISSION);
    return view;
  }

  /** Invoices of a learner visible to the running user, newest first. */
  public static List<Student_Invoice__c> learnerInvoices(Id learnerAccountId) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Issue_Date__c,
        Due_Date__c,
        Total__c,
        Amount_Paid__c,
        Balance_Due__c,
        Overdue__c,
        Enrolment__r.CourseOffering.Name
      FROM Student_Invoice__c
      WHERE Learner_Account__c = :learnerAccountId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 100
    ];
  }

  /** Receivables overview for the Finance Desk (records visible to the running user). */
  public static FinanceDesk financeDesk() {
    FinanceDesk desk = new FinanceDesk();
    for (AggregateResult row : [
      SELECT Overdue__c overdue, SUM(Balance_Due__c) balance, COUNT(Id) total
      FROM Student_Invoice__c
      WHERE Status__c IN :OPEN_STATUSES
      WITH USER_MODE
      GROUP BY Overdue__c
    ]) {
      Decimal balance = nvl((Decimal) row.get('balance'));
      desk.outstanding += balance;
      if ((Boolean) row.get('overdue')) {
        desk.overdueAmount = balance;
        desk.overdueCount = (Integer) row.get('total');
      }
    }
    Date monthStart = Date.today().toStartOfMonth();
    desk.collectedThisMonth = nvl(
      (Decimal) [
          SELECT SUM(Amount__c) total
          FROM Student_Payment__c
          WHERE Status__c = 'Confirmed' AND Payment_Date__c >= :monthStart
          WITH USER_MODE
        ][0]
        .get('total')
    );
    desk.overdue = [
      SELECT
        Id,
        Name,
        Due_Date__c,
        Balance_Due__c,
        Status__c,
        Bill_To__r.Name,
        Learner__r.Name
      FROM Student_Invoice__c
      WHERE Overdue__c = TRUE
      WITH USER_MODE
      ORDER BY Due_Date__c ASC
      LIMIT 50
    ];
    desk.pending = paymentList('Status__c = \'Pending\'');
    desk.exceptions = paymentList(
      'Status__c = \'Confirmed\' AND Reconciliation_Status__c = \'Exception\''
    );
    desk.recent = paymentList('Status__c = \'Confirmed\'');
    desk.canManage = FeatureManagement.checkPermission(MANAGE_PERMISSION);
    return desk;
  }

  private static List<Student_Payment__c> paymentList(String condition) {
    return Database.query(
      'SELECT Id, Name, Amount__c, Unallocated_Amount__c, Method__c, Status__c, Payment_Date__c, ' +
        'Reference__c, Receipt_Number__c, Reconciliation_Status__c, Reconciliation_Note__c, ' +
        'Payer__r.Name, Learner__r.Name, Student_Invoice__c, Student_Invoice__r.Name ' +
        'FROM Student_Payment__c WHERE ' +
        condition +
        ' ORDER BY CreatedDate DESC LIMIT 50',
      AccessLevel.USER_MODE
    );
  }

  /** The active fee-paying guardian of a learner, or the learner when none is set. */
  public static Id billToFor(Id learnerContactId) {
    for (ContactContactRelation rel : [
      SELECT ContactId
      FROM ContactContactRelation
      WHERE
        RelatedContactId = :learnerContactId
        AND PartyRoleRelationId = :GuardianRelationshipService.guardianRoleRelationId()
        AND IsActive = TRUE
        AND Is_Fee_Payer__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ]) {
      return rel.ContactId;
    }
    return learnerContactId;
  }

  // --------------------------------------------------------------- helpers

  /** Sets invoice status from its paid amount and keeps enrolment billing status in step. */
  @TestVisible
  private static void refreshInvoices(Set<Id> invoiceIds) {
    if (invoiceIds.isEmpty()) {
      return;
    }
    List<SObject> updates = new List<SObject>();
    Set<Id> enrolmentIds = new Set<Id>();
    for (Student_Invoice__c invoice : [
      SELECT Id, Status__c, Total__c, Amount_Paid__c, Enrolment__c
      FROM Student_Invoice__c
      WHERE Id IN :invoiceIds
      WITH SYSTEM_MODE
    ]) {
      enrolmentIds.add(invoice.Enrolment__c);
      if (
        !OPEN_STATUSES.contains(invoice.Status__c) &&
        invoice.Status__c != 'Paid'
      ) {
        continue;
      }
      Decimal paid = nvl(invoice.Amount_Paid__c);
      String status = paid >= nvl(invoice.Total__c)
        ? 'Paid'
        : paid > 0 ? 'Partially Paid' : 'Issued';
      if (status != invoice.Status__c) {
        updates.add(
          new Student_Invoice__c(Id = invoice.Id, Status__c = status)
        );
      }
    }
    new Writer().updateRecords(updates);
    refreshEnrolments(enrolmentIds);
  }

  private static void refreshEnrolments(Set<Id> enrolmentIds) {
    enrolmentIds.remove(null);
    if (enrolmentIds.isEmpty()) {
      return;
    }
    Map<Id, List<Student_Invoice__c>> byEnrolment = new Map<Id, List<Student_Invoice__c>>();
    for (Id enrolmentId : enrolmentIds) {
      byEnrolment.put(enrolmentId, new List<Student_Invoice__c>());
    }
    for (Student_Invoice__c invoice : [
      SELECT Enrolment__c, Status__c, Amount_Paid__c
      FROM Student_Invoice__c
      WHERE Enrolment__c IN :enrolmentIds AND Status__c != 'Cancelled'
      WITH SYSTEM_MODE
    ]) {
      byEnrolment.get(invoice.Enrolment__c).add(invoice);
    }
    List<SObject> updates = new List<SObject>();
    for (CourseOfferingParticipant enrolment : [
      SELECT Id, Billing_Status__c
      FROM CourseOfferingParticipant
      WHERE Id IN :enrolmentIds
      WITH SYSTEM_MODE
    ]) {
      String status = billingStatus(byEnrolment.get(enrolment.Id));
      if (status != enrolment.Billing_Status__c) {
        updates.add(
          new CourseOfferingParticipant(
            Id = enrolment.Id,
            Billing_Status__c = status
          )
        );
      }
    }
    new Writer().updateRecords(updates);
  }

  @TestVisible
  private static String billingStatus(List<Student_Invoice__c> invoices) {
    if (invoices.isEmpty()) {
      return 'Not Invoiced';
    }
    Boolean allPaid = true;
    Boolean anyPaid = false;
    for (Student_Invoice__c invoice : invoices) {
      allPaid &= invoice.Status__c == 'Paid';
      anyPaid |= nvl(invoice.Amount_Paid__c) > 0;
    }
    return allPaid ? 'Paid' : anyPaid ? 'Partially Paid' : 'Invoiced';
  }

  private static void stampIssue(
    Student_Invoice__c invoice,
    BranchPolicy policy
  ) {
    invoice.Status__c = 'Issued';
    invoice.Issue_Date__c = Date.today();
    invoice.Due_Date__c = Date.today().addDays(policy.invoiceDueDays());
  }

  private static PaymentResult result(Id paymentId) {
    Student_Payment__c payment = loadPayment(paymentId, false);
    PaymentResult outcome = new PaymentResult();
    outcome.paymentId = payment.Id;
    outcome.status = payment.Status__c;
    outcome.reconciliationStatus = payment.Reconciliation_Status__c;
    outcome.receiptNumber = payment.Receipt_Number__c;
    outcome.allocated = nvl(payment.Allocated_Amount__c);
    outcome.unallocated = payment.Status__c == 'Confirmed'
      ? payment.Amount__c - outcome.allocated
      : 0;
    return outcome;
  }

  private static Student_Payment__c loadPayment(Id paymentId, Boolean lock) {
    List<Student_Payment__c> rows = lock
      ? [
          SELECT
            Id,
            Name,
            Amount__c,
            Allocated_Amount__c,
            Status__c,
            Reconciliation_Status__c,
            Receipt_Number__c,
            Payer__c,
            Student_Invoice__c
          FROM Student_Payment__c
          WHERE Id = :paymentId
          WITH SYSTEM_MODE
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Name,
            Amount__c,
            Allocated_Amount__c,
            Status__c,
            Reconciliation_Status__c,
            Receipt_Number__c,
            Payer__c,
            Student_Invoice__c
          FROM Student_Payment__c
          WHERE Id = :paymentId
          WITH SYSTEM_MODE
        ];
    if (rows.isEmpty()) {
      throw new AppException('Payment not found.');
    }
    return rows[0];
  }

  private static Student_Invoice__c loadInvoice(Id invoiceId) {
    List<Student_Invoice__c> rows = [
      SELECT
        Id,
        Status__c,
        Amount_Paid__c,
        Bill_To__c,
        Learner__c,
        Branch__c,
        Enrolment__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Invoice not found.');
    }
    return rows[0];
  }

  private static CourseOfferingParticipant loadEnrolment(Id enrolmentId) {
    List<CourseOfferingParticipant> rows = [
      SELECT
        Id,
        ParticipantContactId,
        ParticipantContact.AccountId,
        ParticipationStatus,
        Branch__c,
        Discount_Approval_Status__c
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Enrolment not found or not accessible.');
    }
    return rows[0];
  }

  private static Branch__c loadBranch(Id branchId) {
    if (branchId == null) {
      return null;
    }
    return [
      SELECT Id, Invoice_Prefix__c, Invoice_Due_Days__c
      FROM Branch__c
      WHERE Id = :branchId
      WITH SYSTEM_MODE
    ];
  }

  /** Locked queries cannot use ORDER BY, so order by due date (then number) here. */
  @TestVisible
  private static List<Student_Invoice__c> oldestDueFirst(
    List<Student_Invoice__c> invoices
  ) {
    List<Student_Invoice__c> sorted = new List<Student_Invoice__c>();
    for (Student_Invoice__c invoice : invoices) {
      Integer index = 0;
      while (index < sorted.size() && !dueBefore(invoice, sorted[index])) {
        index++;
      }
      if (index == sorted.size()) {
        sorted.add(invoice);
      } else {
        sorted.add(index, invoice);
      }
    }
    return sorted;
  }

  private static Boolean dueBefore(Student_Invoice__c a, Student_Invoice__c b) {
    Date dueA = a.Due_Date__c == null
      ? Date.newInstance(4000, 1, 1)
      : a.Due_Date__c;
    Date dueB = b.Due_Date__c == null
      ? Date.newInstance(4000, 1, 1)
      : b.Due_Date__c;
    return dueA < dueB || (dueA == dueB && a.Name < b.Name);
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** Ledger writes, authorised by KEM_Manage_Billing (checked by every public entry point). */
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
