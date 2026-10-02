/**
 * Person account rules: every learner gets exactly one LearnerProfile, which
 * carries the institution student number.
 */
public with sharing class AccountTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> newRecords) {
    LearnerService.ensureProfiles(learnerIds((List<Account>) newRecords));
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    List<Account> changed = (List<Account>) changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{ Account.KEM_Role__c }
    );
    if (!changed.isEmpty()) {
      LearnerService.ensureProfiles(learnerIds(changed));
    }
  }

  private static Set<Id> learnerIds(List<Account> accounts) {
    Set<Id> ids = new Set<Id>();
    for (Account account : accounts) {
      if (
        account.IsPersonAccount && LearnerService.isLearner(account.KEM_Role__c)
      ) {
        ids.add(account.Id);
      }
    }
    return ids;
  }
}
