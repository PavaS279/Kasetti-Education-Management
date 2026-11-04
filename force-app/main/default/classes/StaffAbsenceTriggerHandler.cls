/** Staff absence rules: governed status transitions. */
public with sharing class StaffAbsenceTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Staff_Absence__c.Status__c
    );
  }
}
