/**
 * Application rules: default offer state, eligibility evaluation, governed
 * status and offer transitions, and checklist creation for new applications.
 */
public with sharing class IndividualApplicationTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    List<IndividualApplication> applications = (List<IndividualApplication>) newRecords;
    Boolean startsComplete = ApplicationService.templateHasNoRequiredItems();
    for (IndividualApplication application : applications) {
      if (application.Offer_Status__c == null) {
        application.Offer_Status__c = 'Not Offered';
      }
      application.Checklist_Complete__c = startsComplete;
    }
    ApplicationService.evaluateEligibility(applications);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      IndividualApplication.Status
    );
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      IndividualApplication.Offer_Status__c,
      'Not Offered'
    );
    List<IndividualApplication> changed = (List<IndividualApplication>) changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{
        IndividualApplication.Learning_Course__c,
        IndividualApplication.AccountId
      }
    );
    List<IndividualApplication> toEvaluate = new List<IndividualApplication>();
    for (IndividualApplication application : changed) {
      if (application.Eligibility_Status__c != 'Overridden') {
        toEvaluate.add(application);
      }
    }
    ApplicationService.evaluateEligibility(toEvaluate);
  }

  protected override void afterInsert(List<SObject> newRecords) {
    Set<Id> collegeIds = new Set<Id>();
    Set<Id> openCollegeIds = new Set<Id>();
    Set<Id> learningCentreIds = new Set<Id>();
    for (SObject record : newRecords) {
      IndividualApplication application = (IndividualApplication) record;
      if (application.College_Mode__c) {
        collegeIds.add(application.Id);
        if (
          application.College_Stage__c == null ||
          application.College_Stage__c == 'Processing' ||
          application.College_Stage__c == 'In Review'
        ) {
          openCollegeIds.add(application.Id);
        }
      } else {
        learningCentreIds.add(application.Id);
      }
    }
    ApplicationService.createChecklists(learningCentreIds);
    CollegeDocumentService.createChecklists(collegeIds);
    evaluateCollege(newRecords, openCollegeIds);
  }

  /** College verdicts straight away for desk-sized inserts; larger loads are queued. */
  private static void evaluateCollege(
    List<SObject> newRecords,
    Set<Id> collegeIds
  ) {
    if (collegeIds.isEmpty()) {
      return;
    }
    if (collegeIds.size() <= 5) {
      for (Id applicationId : collegeIds) {
        AdmissionEligibilityService.evaluate(applicationId);
      }
      return;
    }
    Set<Id> students = new Set<Id>();
    for (SObject record : newRecords) {
      IndividualApplication application = (IndividualApplication) record;
      if (application.College_Mode__c && application.AccountId != null) {
        students.add(application.AccountId);
      }
    }
    System.enqueueJob(new CollegeEligibilityReevaluationJob(students));
  }
}
