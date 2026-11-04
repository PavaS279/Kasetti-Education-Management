trigger BranchStaffTrigger on Branch_Staff__c(before insert, before update) {
  new BranchStaffTriggerHandler().run();
}
