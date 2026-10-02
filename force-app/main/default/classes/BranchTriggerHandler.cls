/**
 * Keeps branch managers' edit access in step with Branch_Manager__c using
 * Apex managed sharing (row cause Branch_Manager__c). Branch is Public Read
 * Only, so this share is what lets a manager maintain their branch policies.
 */
public without sharing class BranchTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> newRecords) {
    syncManagerShares((List<Branch__c>) newRecords, null);
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    List<Branch__c> changed = (List<Branch__c>) changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{ Branch__c.Branch_Manager__c }
    );
    if (!changed.isEmpty()) {
      syncManagerShares(changed, oldMap);
    }
  }

  private static void syncManagerShares(
    List<Branch__c> branches,
    Map<Id, SObject> oldMap
  ) {
    String rowCause = Schema.Branch__Share.RowCause.Branch_Manager__c;
    if (oldMap != null) {
      Database.delete(
        [
          SELECT Id
          FROM Branch__Share
          WHERE
            ParentId IN :new Map<Id, Branch__c>(branches).keySet()
            AND RowCause = :rowCause
          WITH SYSTEM_MODE
        ],
        AccessLevel.SYSTEM_MODE
      );
    }
    List<Branch__Share> shares = new List<Branch__Share>();
    for (Branch__c branch : branches) {
      if (
        branch.Branch_Manager__c != null &&
        branch.Branch_Manager__c != branch.OwnerId
      ) {
        shares.add(
          new Branch__Share(
            ParentId = branch.Id,
            UserOrGroupId = branch.Branch_Manager__c,
            AccessLevel = 'Edit',
            RowCause = rowCause
          )
        );
      }
    }
    List<Database.SaveResult> results = Database.insert(
      shares,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Logger.errors('BranchTriggerHandler.syncManagerShares', results);
  }
}
