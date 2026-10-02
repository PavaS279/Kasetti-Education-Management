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
    ApplicationService.createChecklists(
      new Map<Id, SObject>(newRecords).keySet()
    );
  }
}
