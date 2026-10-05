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
  public static final String MONTHLY = 'Monthly';
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
    public List<Instalment__c> instalments;
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

  /**
   * Raises an invoice for the enrolment's uninvoiced fee lines; issues it when
   * issueNow is true. One-time and term lines are billed once. Monthly lines are
   * billed one calendar period at a time: the first period when the enrolment is
   * first invoiced, then every period whose start date has arrived (the
   * recurring billing job raises those automatically).
   */
  public static Id createInvoice(Id enrolmentId, Boolean issueNow) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    return raiseInvoice(
      loadEnrolment(enrolmentId, true),
      issueNow,
      Date.today()
    );
  }

  /**
   * System entry point for RecurringBillingJob: bills the monthly periods due on
   * or before asOf for an enrolment already on recurring billing.
   */
  public static Id billDuePeriods(Id enrolmentId, Date asOf) {
    return raiseInvoice(loadEnrolment(enrolmentId, false), true, asOf);
  }

  /** When set (by a batch job), invoice PDFs are collected here instead of queued one by one. */
  public static Set<Id> deferredDocuments;

  private static Id raiseInvoice(
    CourseOfferingParticipant enrolment,
    Boolean issueNow,
    Date asOf
  ) {
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
        Billing_Frequency__c,
        Description__c,
        Unit_Amount__c,
        Discount_Amount__c,
        Tax_Amount__c,
        Line_Total__c,
        Next_Bill_Date__c,
        Periods_Billed__c
      FROM Enrolment_Fee_Line__c
      WHERE Enrolment__c = :enrolment.Id AND Invoiced__c = FALSE
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    List<Invoice_Line__c> lines = new List<Invoice_Line__c>();
    List<SObject> updates = new List<SObject>();
    Date firstPeriod;
    Date lastPeriod;
    Date nextDue;
    for (Enrolment_Fee_Line__c feeLine : feeLines) {
      if (feeLine.Billing_Frequency__c != MONTHLY) {
        lines.add(invoiceLine(feeLine, feeLine.Description__c));
        updates.add(
          new Enrolment_Fee_Line__c(Id = feeLine.Id, Invoiced__c = true)
        );
        continue;
      }
      List<Date> periods = duePeriods(feeLine, enrolment, asOf);
      if (periods.isEmpty()) {
        nextDue = earliest(nextDue, feeLine.Next_Bill_Date__c);
        continue;
      }
      for (Date periodStart : periods) {
        Invoice_Line__c line = invoiceLine(
          feeLine,
          (nvlText(feeLine.Description__c) +
            ' (' +
            periodLabel(periodStart) +
            ')')
            .left(255)
        );
        line.Period_Start__c = periodStart;
        line.Period_End__c = periodEnd(periodStart, enrolment.EndDate);
        lines.add(line);
        firstPeriod = earliest(firstPeriod, periodStart);
        lastPeriod = lastPeriod == null ||
          periodStart > lastPeriod
          ? periodStart
          : lastPeriod;
      }
      Date following = periods[periods.size() - 1].addMonths(1);
      updates.add(
        new Enrolment_Fee_Line__c(
          Id = feeLine.Id,
          Next_Bill_Date__c = following,
          Periods_Billed__c = nvl(feeLine.Periods_Billed__c) + periods.size(),
          Invoiced__c = enrolment.EndDate != null &&
            following > enrolment.EndDate
        )
      );
    }
    if (lines.isEmpty()) {
      throw new AppException(
        nextDue == null
          ? 'There is nothing left to invoice on this enrolment.'
          : 'Nothing is due yet. The next monthly period is billed on ' +
            nextDue.format() +
            '.'
      );
    }
    BranchPolicy policy = new BranchPolicy(loadBranch(enrolment.Branch__c));
    Student_Invoice__c invoice = new Student_Invoice__c(
      Name = 'DRAFT',
      Enrolment__c = enrolment.Id,
      Learner__c = enrolment.ParticipantContactId,
      Learner_Account__c = enrolment.ParticipantContact.AccountId,
      Bill_To__c = billToFor(enrolment.ParticipantContactId),
      Branch__c = enrolment.Branch__c,
      Status__c = 'Draft',
      Billing_Period__c = firstPeriod == null
        ? null
        : firstPeriod == lastPeriod
            ? periodLabel(firstPeriod)
            : periodLabel(firstPeriod) + ' - ' + periodLabel(lastPeriod)
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
    updates.add(
      new Student_Invoice__c(
        Id = invoice.Id,
        Name = policy.invoicePrefix() + '-' + numbered.Sequence__c
      )
    );
    for (Invoice_Line__c line : lines) {
      line.Student_Invoice__c = invoice.Id;
    }
    writer.insertRecords(lines);
    writer.updateRecords(updates);
    refreshInvoices(new Set<Id>{ invoice.Id });
    if (issueNow == true) {
      CreditService.autoApply(new Set<Id>{ invoice.Id });
      MessageService.invoicesIssued(new Set<Id>{ invoice.Id });
      queueInvoiceDocuments(new Set<Id>{ invoice.Id });
    }
    return invoice.Id;
  }

  /** Start dates of the monthly periods to bill now (at most a year of catch-up). */
  @TestVisible
  private static List<Date> duePeriods(
    Enrolment_Fee_Line__c feeLine,
    CourseOfferingParticipant enrolment,
    Date asOf
  ) {
    List<Date> periods = new List<Date>();
    Date next = feeLine.Next_Bill_Date__c;
    if (next == null) {
      // First invoice: the first period is billed up front.
      next = enrolment.StartDate == null ? asOf : enrolment.StartDate;
      periods.add(next);
      next = next.addMonths(1);
    }
    while (
      next <= asOf &&
      (enrolment.EndDate == null ||
      next <= enrolment.EndDate) &&
      periods.size() < 12
    ) {
      periods.add(next);
      next = next.addMonths(1);
    }
    return periods;
  }

  private static Invoice_Line__c invoiceLine(
    Enrolment_Fee_Line__c feeLine,
    String description
  ) {
    return new Invoice_Line__c(
      Enrolment_Fee_Line__c = feeLine.Id,
      Fee_Type__c = feeLine.Fee_Type__c,
      Description__c = description,
      Unit_Amount__c = feeLine.Unit_Amount__c,
      Discount_Amount__c = feeLine.Discount_Amount__c,
      Tax_Amount__c = feeLine.Tax_Amount__c,
      Line_Total__c = feeLine.Line_Total__c
    );
  }

  @TestVisible
  private static String periodLabel(Date periodStart) {
    return Datetime.newInstance(periodStart, Time.newInstance(12, 0, 0, 0))
      .format('MMM yyyy');
  }

  private static Date periodEnd(Date periodStart, Date enrolmentEnd) {
    Date periodEnd = periodStart.addMonths(1).addDays(-1);
    return enrolmentEnd != null &&
      enrolmentEnd < periodEnd
      ? enrolmentEnd
      : periodEnd;
  }

  private static Date earliest(Date a, Date b) {
    return a == null || (b != null && b < a) ? b : a;
  }

  private static String nvlText(String value) {
    return value == null ? '' : value;
  }

  private static void queueInvoiceDocuments(Set<Id> invoiceIds) {
    if (deferredDocuments != null) {
      deferredDocuments.addAll(invoiceIds);
    } else {
      DocumentService.enqueue(invoiceIds, DocumentService.INVOICE);
    }
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
    CreditService.autoApply(new Set<Id>{ invoiceId });
    MessageService.invoicesIssued(new Set<Id>{ invoiceId });
    DocumentService.enqueue(new Set<Id>{ invoiceId }, DocumentService.INVOICE);
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
    // Released lines become billable again; a monthly line steps back to the
    // first cancelled period.
    Map<Id, Enrolment_Fee_Line__c> released = new Map<Id, Enrolment_Fee_Line__c>();
    for (Invoice_Line__c line : [
      SELECT
        Enrolment_Fee_Line__c,
        Enrolment_Fee_Line__r.Periods_Billed__c,
        Period_Start__c
      FROM Invoice_Line__c
      WHERE Student_Invoice__c = :invoiceId AND Enrolment_Fee_Line__c != NULL
      WITH SYSTEM_MODE
    ]) {
      Enrolment_Fee_Line__c feeLine = released.get(line.Enrolment_Fee_Line__c);
      if (feeLine == null) {
        feeLine = new Enrolment_Fee_Line__c(
          Id = line.Enrolment_Fee_Line__c,
          Invoiced__c = false
        );
        released.put(feeLine.Id, feeLine);
      }
      if (line.Period_Start__c != null) {
        feeLine.Periods_Billed__c =
          (feeLine.Periods_Billed__c == null
            ? nvl(line.Enrolment_Fee_Line__r.Periods_Billed__c)
            : feeLine.Periods_Billed__c) - 1;
        feeLine.Next_Bill_Date__c = earliest(
          feeLine.Next_Bill_Date__c,
          line.Period_Start__c
        );
      }
    }
    for (Enrolment_Fee_Line__c feeLine : released.values()) {
      if (feeLine.Periods_Billed__c != null && feeLine.Periods_Billed__c <= 0) {
        feeLine.Periods_Billed__c = 0;
        feeLine.Next_Bill_Date__c = null;
      }
    }
    updates.addAll(released.values());
    Writer writer = new Writer();
    writer.deleteRecords(
      [
        SELECT Id
        FROM Instalment__c
        WHERE Student_Invoice__c = :invoiceId
        WITH SYSTEM_MODE
      ]
    );
    writer.updateRecords(updates);
    refreshEnrolments(new Set<Id>{ invoice.Enrolment__c });
  }

  // ----------------------------------------------------------- instalments

  public class PlanRequest {
    @AuraEnabled
    public Id invoiceId { get; set; }
    @AuraEnabled
    public Integer count { get; set; }
    @AuraEnabled
    public Date firstDueDate { get; set; }
    @AuraEnabled
    public Integer intervalMonths { get; set; }
  }

  public class PlannedInstalment {
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
  }

  /** The schedule a plan would create, without saving it. */
  public static List<PlannedInstalment> previewPlan(PlanRequest request) {
    Student_Invoice__c invoice = loadPlanInvoice(request);
    return splitPlan(
      invoice.Total__c,
      request.count,
      request.firstDueDate,
      request.intervalMonths == null ? 1 : request.intervalMonths
    );
  }

  /**
   * Splits an issued invoice into 2-12 instalments. Payments keep allocating to
   * the invoice as a whole; they settle instalments in order and the invoice's
   * due date follows the first unpaid instalment, so overdue tracking and
   * reminders work per instalment.
   */
  public static void createPlan(PlanRequest request) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Invoice__c invoice = loadPlanInvoice(request);
    if (nvl(invoice.Instalment_Count__c) > 0) {
      throw new AppException('This invoice already has an instalment plan.');
    }
    List<Instalment__c> rows = new List<Instalment__c>();
    for (
      PlannedInstalment planned : splitPlan(
        invoice.Total__c,
        request.count,
        request.firstDueDate,
        request.intervalMonths == null ? 1 : request.intervalMonths
      )
    ) {
      rows.add(
        new Instalment__c(
          Student_Invoice__c = invoice.Id,
          Sequence__c = planned.sequence,
          Due_Date__c = planned.dueDate,
          Amount__c = planned.amount,
          Amount_Paid__c = 0,
          Status__c = 'Due'
        )
      );
    }
    Writer writer = new Writer();
    writer.insertRecords(rows);
    writer.updateRecords(
      new List<SObject>{
        new Student_Invoice__c(
          Id = invoice.Id,
          Original_Due_Date__c = invoice.Due_Date__c
        )
      }
    );
    refreshInvoices(new Set<Id>{ invoice.Id });
  }

  /** Removes an instalment plan and restores the invoice's original due date. */
  public static void removePlan(Id invoiceId) {
    RecordAccess.assertPermission(MANAGE_PERMISSION);
    Student_Invoice__c invoice = loadInvoice(invoiceId);
    List<Instalment__c> rows = [
      SELECT Id
      FROM Instalment__c
      WHERE Student_Invoice__c = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('This invoice has no instalment plan.');
    }
    Writer writer = new Writer();
    writer.deleteRecords(rows);
    Student_Invoice__c change = new Student_Invoice__c(
      Id = invoiceId,
      Original_Due_Date__c = null
    );
    if (invoice.Original_Due_Date__c != null) {
      change.Due_Date__c = invoice.Original_Due_Date__c;
    }
    writer.updateRecords(new List<SObject>{ change });
  }

  @TestVisible
  private static List<PlannedInstalment> splitPlan(
    Decimal total,
    Integer count,
    Date firstDueDate,
    Integer intervalMonths
  ) {
    if (count == null || count < 2 || count > 12) {
      throw new AppException('Choose between 2 and 12 instalments.');
    }
    if (intervalMonths == null || intervalMonths < 1 || intervalMonths > 6) {
      throw new AppException('Instalments can be 1 to 6 months apart.');
    }
    if (firstDueDate == null) {
      throw new AppException('Choose the first instalment due date.');
    }
    Decimal each = (nvl(total) / count).setScale(2, System.RoundingMode.DOWN);
    List<PlannedInstalment> plan = new List<PlannedInstalment>();
    for (Integer i = 1; i <= count; i++) {
      PlannedInstalment planned = new PlannedInstalment();
      planned.sequence = i;
      planned.dueDate = firstDueDate.addMonths((i - 1) * intervalMonths);
      // The rounding remainder goes on the last instalment.
      planned.amount = i < count ? each : nvl(total) - each * (count - 1);
      plan.add(planned);
    }
    return plan;
  }

  private static Student_Invoice__c loadPlanInvoice(PlanRequest request) {
    if (request == null || request.invoiceId == null) {
      throw new AppException('Choose the invoice.');
    }
    Student_Invoice__c invoice = loadInvoice(request.invoiceId);
    if (!OPEN_STATUSES.contains(invoice.Status__c)) {
      throw new AppException(
        'Only issued invoices with a balance can be paid in instalments.'
      );
    }
    if (
      request.firstDueDate != null &&
      invoice.Issue_Date__c != null &&
      request.firstDueDate < invoice.Issue_Date__c
    ) {
      throw new AppException(
        'The first instalment cannot be due before the invoice date.'
      );
    }
    return invoice;
  }

  /** Settles instalments in order from the invoice's paid amount; due date follows the first unpaid one. */
  private static void refreshInstalments(
    Map<Id, Student_Invoice__c> invoices,
    Map<Id, Student_Invoice__c> changes,
    List<SObject> updates
  ) {
    Map<Id, Decimal> remaining = new Map<Id, Decimal>();
    Set<Id> withPlan = new Set<Id>();
    for (Student_Invoice__c invoice : invoices.values()) {
      if (nvl(invoice.Instalment_Count__c) > 0) {
        withPlan.add(invoice.Id);
        remaining.put(invoice.Id, nvl(invoice.Amount_Paid__c));
      }
    }
    if (withPlan.isEmpty()) {
      return;
    }
    Map<Id, Date> nextDue = new Map<Id, Date>();
    for (Instalment__c row : [
      SELECT
        Id,
        Student_Invoice__c,
        Amount__c,
        Amount_Paid__c,
        Status__c,
        Due_Date__c
      FROM Instalment__c
      WHERE Student_Invoice__c IN :withPlan
      WITH SYSTEM_MODE
      ORDER BY Student_Invoice__c, Sequence__c
    ]) {
      Decimal available = remaining.get(row.Student_Invoice__c);
      Decimal covered = Math.min(available, nvl(row.Amount__c));
      remaining.put(row.Student_Invoice__c, available - covered);
      String status = covered >= nvl(row.Amount__c)
        ? 'Paid'
        : covered > 0 ? 'Partially Paid' : 'Due';
      if (covered != nvl(row.Amount_Paid__c) || status != row.Status__c) {
        updates.add(
          new Instalment__c(
            Id = row.Id,
            Amount_Paid__c = covered,
            Status__c = status
          )
        );
      }
      if (status != 'Paid' && !nextDue.containsKey(row.Student_Invoice__c)) {
        nextDue.put(row.Student_Invoice__c, row.Due_Date__c);
      }
    }
    for (Id invoiceId : nextDue.keySet()) {
      if (nextDue.get(invoiceId) != invoices.get(invoiceId).Due_Date__c) {
        changeFor(changes, invoiceId).Due_Date__c = nextDue.get(invoiceId);
      }
    }
  }

  private static Student_Invoice__c changeFor(
    Map<Id, Student_Invoice__c> changes,
    Id invoiceId
  ) {
    if (!changes.containsKey(invoiceId)) {
      changes.put(invoiceId, new Student_Invoice__c(Id = invoiceId));
    }
    return changes.get(invoiceId);
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
    MessageService.paymentsReceived(new Set<Id>{ paymentId });
    DocumentService.enqueue(new Set<Id>{ paymentId }, DocumentService.RECEIPT);
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
        Original_Due_Date__c,
        Billing_Period__c,
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
        Line_Total__c,
        Period_Start__c,
        Period_End__c
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
    view.instalments = [
      SELECT
        Id,
        Name,
        Sequence__c,
        Due_Date__c,
        Amount__c,
        Amount_Paid__c,
        Status__c,
        Overdue__c
      FROM Instalment__c
      WHERE Student_Invoice__c = :invoiceId
      WITH SYSTEM_MODE
      ORDER BY Sequence__c
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
          WHERE
            Status__c = 'Confirmed'
            AND Method__c != :CreditService.CREDIT_METHOD
            AND Payment_Date__c >= :monthStart
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
    desk.recent = paymentList(
      'Status__c = \'Confirmed\' AND Method__c != \'Credit Note\''
    );
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

  /**
   * Sets invoice status from its paid amount, settles instalments, and keeps
   * enrolment billing status in step.
   */
  public static void refreshInvoices(Set<Id> invoiceIds) {
    if (invoiceIds.isEmpty()) {
      return;
    }
    Map<Id, Student_Invoice__c> changes = new Map<Id, Student_Invoice__c>();
    List<SObject> instalmentUpdates = new List<SObject>();
    Set<Id> enrolmentIds = new Set<Id>();
    Map<Id, Student_Invoice__c> open = new Map<Id, Student_Invoice__c>();
    for (Student_Invoice__c invoice : [
      SELECT
        Id,
        Status__c,
        Total__c,
        Amount_Paid__c,
        Enrolment__c,
        Due_Date__c,
        Instalment_Count__c
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
      open.put(invoice.Id, invoice);
      Decimal paid = nvl(invoice.Amount_Paid__c);
      String status = paid >= nvl(invoice.Total__c)
        ? 'Paid'
        : paid > 0 ? 'Partially Paid' : 'Issued';
      if (status != invoice.Status__c) {
        changeFor(changes, invoice.Id).Status__c = status;
      }
    }
    refreshInstalments(open, changes, instalmentUpdates);
    Writer writer = new Writer();
    writer.updateRecords(changes.values());
    writer.updateRecords(instalmentUpdates);
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
        Total__c,
        Amount_Paid__c,
        Bill_To__c,
        Learner__c,
        Branch__c,
        Enrolment__c,
        Issue_Date__c,
        Due_Date__c,
        Original_Due_Date__c,
        Instalment_Count__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Invoice not found.');
    }
    return rows[0];
  }

  private static CourseOfferingParticipant loadEnrolment(
    Id enrolmentId,
    Boolean userMode
  ) {
    List<CourseOfferingParticipant> rows = Database.queryWithBinds(
      'SELECT Id, ParticipantContactId, ParticipantContact.AccountId, ' +
        'ParticipationStatus, Branch__c, Discount_Approval_Status__c, StartDate, EndDate ' +
        'FROM CourseOfferingParticipant WHERE Id = :enrolmentId',
      new Map<String, Object>{ 'enrolmentId' => enrolmentId },
      userMode ? AccessLevel.USER_MODE : AccessLevel.SYSTEM_MODE
    );
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

    void deleteRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.delete(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
