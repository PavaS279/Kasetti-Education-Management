/** Refund rules: governed status transitions; paid refunds are never deleted. */
public with sharing class RefundTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(newRecords, oldMap, Refund__c.Status__c);
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    for (Refund__c refund : (List<Refund__c>) oldRecords) {
      if (refund.Status__c == 'Paid') {
        refund.addError('Paid refunds cannot be deleted.');
      }
    }
  }

  protected override void afterInsert(List<SObject> newRecords) {
    IntegrationHooks.finance(
      'refund.paid',
      newRecords,
      null,
      Refund__c.Status__c,
      'Paid'
    );
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    IntegrationHooks.finance(
      'refund.paid',
      newRecords,
      oldMap,
      Refund__c.Status__c,
      'Paid'
    );
  }
}
