trigger AdmissionDocumentRuleTrigger on Admission_Document_Rule__c(
  before insert,
  before update
) {
  new AdmissionDocumentRuleTriggerHandler().run();
}
