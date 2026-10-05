/**
 * Nightly recurring billing: raises and issues the next invoice for every
 * active enrolment whose monthly fees have a period starting today or earlier.
 * Only enrolments already on recurring billing (first period invoiced by staff)
 * are picked up. Each enrolment is billed on its own; a failure is logged and
 * does not stop the others.
 * Schedule: KemJobs registers 'KEM Recurring Billing' at 02:10 daily.
 */
public with sharing class RecurringBillingJob implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
  private final Date asOf;
  @TestVisible
  private Integer invoiced = 0;
  @TestVisible
  private Integer failed = 0;

  public RecurringBillingJob() {
    this(Date.today());
  }

  public RecurringBillingJob(Date asOf) {
    this.asOf = asOf;
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
    for (CourseOfferingParticipant enrolment : scope) {
      Savepoint sp = Database.setSavepoint();
      try {
        BillingService.billDuePeriods(enrolment.Id, asOf);
        invoiced++;
      } catch (Exception e) {
        Database.rollback(sp);
        failed++;
        Logger.error('RecurringBillingJob', e, enrolment.Id);
      }
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
        ' failed.'
    );
    Logger.flush();
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(new RecurringBillingJob(), 20);
  }
}
