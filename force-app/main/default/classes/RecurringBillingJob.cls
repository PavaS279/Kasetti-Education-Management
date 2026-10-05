/**
 * Nightly recurring billing: raises and issues the next invoice for every
 * active enrolment whose monthly fees have a period starting today or earlier.
 * Only enrolments already on recurring billing (first period invoiced by staff)
 * are picked up. Each enrolment is billed on its own; a failure is logged and
 * does not stop the others.
 *
 * Scale: billing one enrolment costs about 20 queries, so batches are small
 * (Education Setting Recurring_Billing_Batch_Size, default 5) and an
 * enrolment is left for a follow-up run when the batch is short of query,
 * DML or CPU headroom. Follow-up runs continue while they make progress.
 * Schedule: KemJobs registers 'KEM Recurring Billing' at 02:10 daily.
 */
public with sharing class RecurringBillingJob implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
  private static final Integer MAX_PASSES = 10;
  private static final Integer MIN_QUERY_RESERVE = 25;
  private final Date asOf;
  private final Integer pass;
  @TestVisible
  private Integer deferred = 0;
  /** Test seam: pretends the query limit is this low. */
  @TestVisible
  private static Integer queryLimitOverride;
  @TestVisible
  private Integer invoiced = 0;
  @TestVisible
  private Integer failed = 0;

  public RecurringBillingJob() {
    this(Date.today());
  }

  public RecurringBillingJob(Date asOf) {
    this(asOf, 1);
  }

  private RecurringBillingJob(Date asOf, Integer pass) {
    this.asOf = asOf;
    this.pass = pass;
  }

  public static Integer batchSize() {
    return Math.max(
      1,
      AppSettings.getInteger('Recurring_Billing_Batch_Size', 5)
    );
  }

  /** Starts recurring billing for today. */
  public static Id run() {
    return Database.executeBatch(new RecurringBillingJob(), batchSize());
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM CourseOfferingParticipant
        WHERE
          ParticipationStatus = 'Enrolled'
          AND Discount_Approval_Status__c != 'Pending'
          AND Id IN (
            SELECT Enrolment__c
            FROM Enrolment_Fee_Line__c
            WHERE
              Billing_Frequency__c = :BillingService.MONTHLY
              AND Invoiced__c = FALSE
              AND Periods_Billed__c > 0
              AND Next_Bill_Date__c <= :asOf
          )
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<CourseOfferingParticipant> scope
  ) {
    BillingService.deferredDocuments = new Set<Id>();
    Integer cost = MIN_QUERY_RESERVE;
    for (CourseOfferingParticipant enrolment : scope) {
      if (!hasHeadroom(cost)) {
        deferred++;
        continue;
      }
      Integer queriesBefore = Limits.getQueries();
      Savepoint sp = Database.setSavepoint();
      try {
        BillingService.billDuePeriods(enrolment.Id, asOf);
        invoiced++;
      } catch (Exception e) {
        Database.rollback(sp);
        failed++;
        Logger.error('RecurringBillingJob', e, enrolment.Id);
      }
      cost = Math.max(cost, Limits.getQueries() - queriesBefore);
    }
    Set<Id> documents = BillingService.deferredDocuments;
    BillingService.deferredDocuments = null;
    DocumentService.enqueue(documents, DocumentService.INVOICE);
    Logger.flush();
  }

  public void finish(Database.BatchableContext context) {
    Logger.info(
      'RecurringBillingJob',
      'Recurring billing for ' +
        asOf.format() +
        ': ' +
        invoiced +
        ' invoices raised, ' +
        failed +
        ' failed, ' +
        deferred +
        ' left for a follow-up run (pass ' +
        pass +
        ').'
    );
    if (
      deferred > 0 &&
      invoiced > 0 &&
      pass < MAX_PASSES &&
      !Test.isRunningTest()
    ) {
      Database.executeBatch(
        new RecurringBillingJob(asOf, pass + 1),
        batchSize()
      );
    }
    Logger.flush();
  }

  public void execute(SchedulableContext context) {
    run();
  }

  /** True when one more enrolment (costing about `cost` queries) fits in this transaction. */
  private static Boolean hasHeadroom(Integer cost) {
    Integer queryLimit = queryLimitOverride != null
      ? queryLimitOverride
      : Limits.getLimitQueries();
    return Limits.getQueries() + cost * 1.2 <= queryLimit &&
      Limits.getDmlStatements() + 20 <= Limits.getLimitDmlStatements() &&
      Limits.getCpuTime() < Limits.getLimitCpuTime() * 0.7;
  }
}
