/**
 * Maintains the unique key on Branch_Staff__c so a user holds each role at a
 * branch at most once.
 */
public with sharing class BranchStaffTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    setKeys((List<Branch_Staff__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    setKeys((List<Branch_Staff__c>) newRecords);
  }

  private static void setKeys(List<Branch_Staff__c> assignments) {
    for (Branch_Staff__c assignment : assignments) {
      assignment.Unique_Key__c =
        assignment.Branch__c +
        ':' +
        assignment.User__c +
        ':' +
        assignment.Role__c;
    }
  }
}
