trigger EntranceScoreTrigger on Entrance_Score__c(after insert, after update) {
  new EntranceScoreTriggerHandler().run();
}
