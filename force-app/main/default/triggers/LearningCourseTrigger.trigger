trigger LearningCourseTrigger on LearningCourse(before insert, before update) {
  new LearningCourseTriggerHandler().run();
}
