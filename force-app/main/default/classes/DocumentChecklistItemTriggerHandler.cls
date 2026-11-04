/**
 * Keeps IndividualApplication.Checklist_Complete__c in step with its
 * checklist items. Items on other parent types are ignored.
 */
public with sharing class DocumentChecklistItemTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> newRecords) {
    recalculate(newRecords);
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    recalculate(newRecords);
  }

  protected override void afterDelete(List<SObject> oldRecords) {
    recalculate(oldRecords);
  }

  protected override void afterUndelete(List<SObject> newRecords) {
    recalculate(newRecords);
  }

  private static void recalculate(List<SObject> items) {
    Set<Id> applicationIds = new Set<Id>();
    for (DocumentChecklistItem item : (List<DocumentChecklistItem>) items) {
      if (
        item.ParentRecordId != null &&
        item.ParentRecordId.getSObjectType() ==
        IndividualApplication.SObjectType
      ) {
        applicationIds.add(item.ParentRecordId);
      }
    }
    ApplicationService.refreshChecklistStatus(applicationIds);
  }
}
