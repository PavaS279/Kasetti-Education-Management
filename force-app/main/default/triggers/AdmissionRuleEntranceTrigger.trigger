trigger AdmissionRuleEntranceTrigger on Admission_Rule_Entrance__c(
  before insert,
  before update,
  before delete
) {
  new AdmissionRuleEntranceTriggerHandler().run();
}
