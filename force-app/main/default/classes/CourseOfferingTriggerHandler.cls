/** Class (CourseOffering) rules: governed class status transitions. */
public with sharing class CourseOfferingTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    for (CourseOffering offering : (List<CourseOffering>) newRecords) {
      if (offering.Class_Status__c == null) {
        offering.Class_Status__c = 'Planned';
      }
    }
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      CourseOffering.Class_Status__c,
      'Planned'
    );
  }
}
