public without sharing class CollegeEligibilityReevaluationJob implements Queueable {
  private static final Integer CHUNK_SIZE = 10;
  private Set<Id> studentIds;
  private List<Id> applicationIds;

  public CollegeEligibilityReevaluationJob(Set<Id> studentIds) {
    this.studentIds = studentIds == null ? new Set<Id>() : studentIds.clone();
  }

  @TestVisible
  private CollegeEligibilityReevaluationJob(List<Id> applicationIds) {
    this.applicationIds = applicationIds;
  }

  public void execute(QueueableContext context) {
    List<Id> pending = applicationIds;
    if (pending == null) {
      pending = new List<Id>();
      for (IndividualApplication application : [
        SELECT Id
        FROM IndividualApplication
        WHERE
          AccountId IN :studentIds
          AND Learning_Course__c != NULL
          AND Academic_Year__c != NULL
          AND Entry_Route__c != NULL
          AND Status NOT IN (
            'Application Decision',
            'Enrolled',
            'Withdrawn',
            'Cancelled',
            'Canceled'
          )
          AND (College_Stage__c = NULL
          OR College_Stage__c NOT IN (
            'Application Decision',
            'Fee Pending',
            'Enrolled',
            'Enrollment Failed',
            'Withdrawn'
          ))
        WITH SYSTEM_MODE
        ORDER BY CreatedDate, Id
      ]) {
        pending.add(application.Id);
      }
    }
    Integer count = Math.min(CHUNK_SIZE, pending.size());
    for (Integer index = 0; index < count; index++) {
      AdmissionEligibilityService.evaluate(pending[index]);
    }
    if (pending.size() > count && !Test.isRunningTest()) {
      List<Id> remaining = new List<Id>();
      for (Integer index = count; index < pending.size(); index++) {
        remaining.add(pending[index]);
      }
      System.enqueueJob(new CollegeEligibilityReevaluationJob(remaining));
    }
  }
}
