/** Maintains the programme-scoped college branch code key. */
public inherited sharing class LearningCourseTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    stamp((List<LearningCourse>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<LearningCourse>) newRecords);
  }

  private static void stamp(List<LearningCourse> courses) {
    for (LearningCourse course : courses) {
      course.Branch_Code__c = String.isBlank(course.Branch_Code__c)
        ? null
        : course.Branch_Code__c.trim().toUpperCase();
      course.Branch_Code_Key__c = course.Programme__c == null ||
        course.Branch_Code__c == null
        ? null
        : String.valueOf(course.Programme__c) + '|' + course.Branch_Code__c;
    }
  }
}
