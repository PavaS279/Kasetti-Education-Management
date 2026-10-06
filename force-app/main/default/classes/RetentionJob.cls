/**
 * Nightly at-risk scoring of active enrolments (RetentionService.assess).
 * Schedule: KemJobs ('KEM Retention', 04:05).
 */
public with sharing class RetentionJob implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
  public static final Integer BATCH_SIZE = 200;
  @TestVisible
  private Integer escalated = 0;
  @TestVisible
  private Integer assessed = 0;

  public static Id run() {
    return Database.executeBatch(new RetentionJob(), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM CourseOfferingParticipant
        WHERE ParticipationStatus IN :RetentionService.ACTIVE
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<CourseOfferingParticipant> scope
  ) {
    try {
      escalated += RetentionService.assess(
        new Map<Id, CourseOfferingParticipant>(scope).keySet()
      );
      assessed += scope.size();
    } catch (Exception e) {
      Logger.error('RetentionJob', e, null);
    }
    Logger.flush();
  }

  public void finish(Database.BatchableContext context) {
    Logger.info(
      'RetentionJob',
      'Retention scoring: ' +
        assessed +
        ' enrolments assessed, ' +
        escalated +
        ' newly high risk (follow-up tasks created).'
    );
    Logger.flush();
  }

  public void execute(SchedulableContext context) {
    run();
  }
}
