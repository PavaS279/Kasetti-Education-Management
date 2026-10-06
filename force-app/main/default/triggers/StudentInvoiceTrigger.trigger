trigger StudentInvoiceTrigger on Student_Invoice__c(
  before update,
  before delete,
  after insert,
  after update
) {
  new StudentInvoiceTriggerHandler().run();
}
