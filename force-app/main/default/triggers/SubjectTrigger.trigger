trigger SubjectTrigger on Subject__c(before insert, before update) {
  new SubjectTriggerHandler().run();
}
