trigger CreditNoteTrigger on Credit_Note__c(before update, before delete) {
  new CreditNoteTriggerHandler().run();
}
