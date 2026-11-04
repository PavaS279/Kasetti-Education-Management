trigger CampusBranchTrigger on Campus_Branch__c(before insert, before update) {
  new CampusBranchTriggerHandler().run();
}
