trigger RefundTrigger on Refund__c(before update, before delete) {
  new RefundTriggerHandler().run();
}
