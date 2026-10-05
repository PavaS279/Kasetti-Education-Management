trigger StaffAbsenceTrigger on Staff_Absence__c(before update) {
  new StaffAbsenceTriggerHandler().run();
}
