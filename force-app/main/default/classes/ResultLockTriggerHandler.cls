/**
 * Locks final college results: Final subject and term results cannot be edited
 * or deleted except by ResultService (Dean finalise / reopen). Shared by the
 * Subject_Result__c and Term_Result__c triggers.
 */
public inherited sharing class ResultLockTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    if (ResultService.isUnlocked()) {
      return;
    }
    for (SObject record : newRecords) {
      if (
        oldMap.get(record.Id).get('Status__c') == ResultService.FINAL_STATUS
      ) {
        record.addError(
          'Final results are locked. The Dean can reopen them with a reason.'
        );
      }
    }
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    if (ResultService.isUnlocked()) {
      return;
    }
    for (SObject record : oldRecords) {
      if (record.get('Status__c') == ResultService.FINAL_STATUS) {
        record.addError('Final results cannot be deleted.');
      }
    }
  }
}
