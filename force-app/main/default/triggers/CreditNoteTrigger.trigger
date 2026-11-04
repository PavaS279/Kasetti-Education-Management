trigger CreditNoteTrigger on Credit_Note__c(
  before update,
  before delete,
  after insert,
  after update
) {
  new CreditNoteTriggerHandler().run();
}
