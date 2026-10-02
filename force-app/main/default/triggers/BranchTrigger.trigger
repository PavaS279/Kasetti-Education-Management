trigger BranchTrigger on Branch__c(after insert, after update) {
  new BranchTriggerHandler().run();
}
