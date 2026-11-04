/**
 * Credit note rules: governed status transitions; a credit note that has been
 * used or refunded is part of the ledger and cannot be deleted (void it instead).
 */
public with sharing class CreditNoteTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Credit_Note__c.Status__c
    );
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    for (Credit_Note__c note : (List<Credit_Note__c>) oldRecords) {
      if (
        (note.Amount_Applied__c != null && note.Amount_Applied__c > 0) ||
        (note.Amount_Refunded__c != null &&
        note.Amount_Refunded__c > 0)
      ) {
        note.addError('Credit notes that have been used cannot be deleted.');
      }
    }
  }

  protected override void afterInsert(List<SObject> newRecords) {
    IntegrationHooks.finance(
      'credit_note.issued',
      newRecords,
      null,
      Credit_Note__c.Status__c,
      null
    );
  }
}
