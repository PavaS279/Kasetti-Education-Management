trigger RefundTrigger on Refund__c(
  before update,
  before delete,
  after insert,
  after update
) {
  new RefundTriggerHandler().run();
}
