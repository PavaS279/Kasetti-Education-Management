trigger BranchTrigger on Branch__c(
  before insert,
  before update,
  after insert,
  after update
) {
  new BranchTriggerHandler().run();
}
