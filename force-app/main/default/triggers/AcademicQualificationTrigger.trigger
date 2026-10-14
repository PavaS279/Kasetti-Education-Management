trigger AcademicQualificationTrigger on Academic_Qualification__c(
  after insert,
  after update
) {
  new AcademicQualificationTriggerHandler().run();
}
