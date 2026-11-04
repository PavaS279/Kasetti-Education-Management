/**
 * Invoice rules: governed status transitions; only draft invoices may be
 * deleted (issued invoices are cancelled so the ledger keeps their history).
 */
public with sharing class StudentInvoiceTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Student_Invoice__c.Status__c
    );
  }

  protected override void beforeDelete(List<SObject> oldRecords) {
    for (Student_Invoice__c invoice : (List<Student_Invoice__c>) oldRecords) {
      if (invoice.Status__c != 'Draft') {
        invoice.addError(
          'Issued invoices cannot be deleted. Cancel the invoice instead.'
        );
      }
    }
  }

  protected override void afterInsert(List<SObject> newRecords) {
    IntegrationHooks.finance(
      'invoice.issued',
      newRecords,
      null,
      Student_Invoice__c.Status__c,
      'Issued'
    );
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    IntegrationHooks.finance(
      'invoice.issued',
      newRecords,
      oldMap,
      Student_Invoice__c.Status__c,
      'Issued'
    );
    IntegrationHooks.finance(
      'invoice.cancelled',
      newRecords,
      oldMap,
      Student_Invoice__c.Status__c,
      'Cancelled'
    );
  }
}
