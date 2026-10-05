trigger CourseOfferingTrigger on CourseOffering(
  before insert,
  before update,
  after update
) {
  new CourseOfferingTriggerHandler().run();
}
