public without sharing class AcademicQualificationTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> records) {
    enqueue((List<Academic_Qualification__c>) records);
  }
  protected override void afterUpdate(
    List<SObject> records,
    Map<Id, SObject> oldMap
  ) {
    enqueue((List<Academic_Qualification__c>) records);
  }
  private static void enqueue(List<Academic_Qualification__c> records) {
    Set<Id> students = new Set<Id>();
    for (Academic_Qualification__c value : records)
      if (value.Verified__c && value.Student__c != null)
        students.add(value.Student__c);
    if (!students.isEmpty())
      System.enqueueJob(new CollegeEligibilityReevaluationJob(students));
  }
}
