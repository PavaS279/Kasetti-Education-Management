trigger StudentPaymentTrigger on Student_Payment__c(
  before update,
  before delete
) {
  new StudentPaymentTriggerHandler().run();
}
