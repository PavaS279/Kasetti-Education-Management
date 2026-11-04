trigger SubjectResultTrigger on Subject_Result__c(
  before update,
  before delete
) {
  new ResultLockTriggerHandler().run();
}
