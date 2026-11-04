trigger StudentPaymentTrigger on Student_Payment__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update
) {
  new StudentPaymentTriggerHandler().run();
}
