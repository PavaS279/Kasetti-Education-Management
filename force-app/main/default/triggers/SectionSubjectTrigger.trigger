trigger SectionSubjectTrigger on Section_Subject__c(
  before insert,
  before update
) {
  new SectionSubjectTriggerHandler().run();
}
