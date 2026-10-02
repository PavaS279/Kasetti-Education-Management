trigger CourseOfferingTrigger on CourseOffering(before insert, before update) {
  new CourseOfferingTriggerHandler().run();
}
