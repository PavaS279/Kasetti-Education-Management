trigger AdmissionRuleTrigger on Admission_Rule__c(
  before insert,
  before update
) {
  new AdmissionRuleTriggerHandler().run();
}
