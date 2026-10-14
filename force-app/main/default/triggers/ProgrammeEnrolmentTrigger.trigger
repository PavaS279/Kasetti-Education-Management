trigger ProgrammeEnrolmentTrigger on Programme_Enrolment__c(
  before insert,
  before update
) {
  if (Trigger.isBefore && Trigger.isInsert)
    ProgrammeEnrolmentTriggerHandler.beforeInsert(Trigger.new);
  if (Trigger.isBefore && Trigger.isUpdate)
    ProgrammeEnrolmentTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
}
