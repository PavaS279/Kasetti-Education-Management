trigger ClassSessionTrigger on Class_Session__c(before insert, before update) {
  new ClassSessionTriggerHandler().run();
}
