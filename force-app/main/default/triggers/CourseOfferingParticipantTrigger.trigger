trigger CourseOfferingParticipantTrigger on CourseOfferingParticipant(
  before update,
  after insert,
  after update,
  after delete
) {
  new CourseOfferingParticipantTriggerHandler().run();
}
