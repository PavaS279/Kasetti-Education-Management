trigger StudentInvoiceTrigger on Student_Invoice__c(
  before update,
  before delete
) {
  new StudentInvoiceTriggerHandler().run();
}
