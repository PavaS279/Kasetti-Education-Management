/**
 * Nightly college admissions run (KEM College Admissions): first expires overdue
 * provisional enrolments and sends payment-due reminders, then chains a recount
 * of every campus-branch intake from the seat-reservation ledger.
 */
public without sharing class CollegeAdmissionsJob implements Database.Batchable<SObject>, Schedulable {
  public static final String PROVISIONAL = 'Provisional';
  public static final String RECONCILE = 'Reconcile';

  private final String mode;
  @TestVisible
  private Date today = Date.today();

  public CollegeAdmissionsJob(String mode) {
    this.mode = mode;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    if (mode == RECONCILE) {
      return Database.getQueryLocator(
        [
          SELECT
            Id,
            Reserved_Regular__c,
            Reserved_Lateral__c,
            Finalised_Regular__c,
            Finalised_Lateral__c
          FROM Campus_Branch__c
        ]
      );
    }
    Date reminderDay = today.addDays(CollegeProvisionalService.REMINDER_DAYS);
    return Database.getQueryLocator(
      [
        SELECT Id, Status__c, Payment_Due_By__c, Expiry_Reminder_Sent__c
        FROM Programme_Enrolment__c
        WHERE
          Status__c = 'Provisional'
          AND (Payment_Due_By__c < :today
          OR Payment_Due_By__c = :reminderDay)
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (mode == RECONCILE) {
      reconcile((List<Campus_Branch__c>) scope);
      return;
    }
    List<Programme_Enrolment__c> values = (List<Programme_Enrolment__c>) scope;
    CollegeProvisionalService.processOverdue(values, today);
    CollegeProvisionalService.sendReminders(values, today);
  }

  public void finish(Database.BatchableContext context) {
    if (mode == PROVISIONAL && !Test.isRunningTest()) {
      Database.executeBatch(new CollegeAdmissionsJob(RECONCILE), 50);
    }
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(this, mode == RECONCILE ? 50 : 5);
  }

  /** Recounts each intake under lock and logs any counter that had drifted. */
  @TestVisible
  private static Integer reconcile(List<Campus_Branch__c> intakes) {
    Map<Id, Campus_Branch__c> before = new Map<Id, Campus_Branch__c>(intakes);
    for (Campus_Branch__c intake : intakes) {
      CollegeSeatService.reconcile(intake.Id);
    }
    Integer drifted = 0;
    for (Campus_Branch__c after : [
      SELECT
        Id,
        Reserved_Regular__c,
        Reserved_Lateral__c,
        Finalised_Regular__c,
        Finalised_Lateral__c
      FROM Campus_Branch__c
      WHERE Id IN :before.keySet()
      WITH SYSTEM_MODE
    ]) {
      Campus_Branch__c old = before.get(after.Id);
      if (
        nvl(old.Reserved_Regular__c) != nvl(after.Reserved_Regular__c) ||
        nvl(old.Reserved_Lateral__c) != nvl(after.Reserved_Lateral__c) ||
        nvl(old.Finalised_Regular__c) != nvl(after.Finalised_Regular__c) ||
        nvl(old.Finalised_Lateral__c) != nvl(after.Finalised_Lateral__c)
      ) {
        drifted++;
        Logger.warn(
          'CollegeAdmissionsJob.reconcile',
          'Intake counters corrected from reserved ' +
            nvl(old.Reserved_Regular__c) +
            '/' +
            nvl(old.Reserved_Lateral__c) +
            ', finalised ' +
            nvl(old.Finalised_Regular__c) +
            '/' +
            nvl(old.Finalised_Lateral__c) +
            ' to reserved ' +
            nvl(after.Reserved_Regular__c) +
            '/' +
            nvl(after.Reserved_Lateral__c) +
            ', finalised ' +
            nvl(after.Finalised_Regular__c) +
            '/' +
            nvl(after.Finalised_Lateral__c) +
            ' (regular/lateral).',
          after.Id
        );
      }
    }
    Logger.flush();
    return drifted;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
