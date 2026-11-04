/**
 * Payment rules: governed status transitions; confirmed payments are never
 * deleted (they are part of the reconciled ledger).
 */
public with sharing class StudentPaymentTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    CollegePaymentPolicy.validate((List<Student_Payment__c>) newRecords, true);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    CollegePaymentPolicy.validate((List<Student_Payment__c>) newRecords, false);
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Student_Payment__c.Status__c
    );
    if (!BillingService.confirmingPayments) {
      for (Student_Payment__c payment : (List<Student_Payment__c>) newRecords) {
        Student_Payment__c old = (Student_Payment__c) oldMap.get(payment.Id);
        if (old.Status__c == 'Pending' && payment.Status__c == 'Confirmed') {
          payment.addError(
            Student_Payment__c.Status__c,
            'Confirm the payment from the Finance Desk so it is allocated and the receipt is issued.'
          );
        }
      }
    }
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
