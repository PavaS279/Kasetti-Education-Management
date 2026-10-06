/**
 * Payment rules: governed status transitions; confirmed payments are never
 * deleted (they are part of the reconciled ledger).
 */
public with sharing class StudentPaymentTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Student_Payment__c.Status__c
    );
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    for (Student_Payment__c payment : (List<Student_Payment__c>) oldRecords) {
      if (payment.Status__c == 'Confirmed') {
        payment.addError('Confirmed payments cannot be deleted.');
      }
    }
  }

  protected override void afterInsert(List<SObject> newRecords) {
    IntegrationHooks.finance(
      'payment.confirmed',
      newRecords,
      null,
      Student_Payment__c.Status__c,
      'Confirmed'
    );
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    IntegrationHooks.finance(
      'payment.confirmed',
      newRecords,
      oldMap,
      Student_Payment__c.Status__c,
      'Confirmed'
    );
  }
}
