trigger CourseOfferingTrigger on CourseOffering(
  before insert,
  before update,
  after insert,
  after update
) {
  new CourseOfferingTriggerHandler().run();
}
