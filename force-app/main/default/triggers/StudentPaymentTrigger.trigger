trigger StudentPaymentTrigger on Student_Payment__c(
  before update,
  before delete,
  after insert,
  after update
) {
  new StudentPaymentTriggerHandler().run();
}
