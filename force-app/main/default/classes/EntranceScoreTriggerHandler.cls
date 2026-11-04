public without sharing class EntranceScoreTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> records) {
    enqueue((List<Entrance_Score__c>) records);
  }
  protected override void afterUpdate(
    List<SObject> records,
    Map<Id, SObject> oldMap
  ) {
    enqueue((List<Entrance_Score__c>) records);
  }
  private static void enqueue(List<Entrance_Score__c> records) {
    Set<Id> students = new Set<Id>();
    for (Entrance_Score__c value : records)
      if (value.Verified__c && value.Student__c != null)
        students.add(value.Student__c);
    if (!students.isEmpty())
      System.enqueueJob(new CollegeEligibilityReevaluationJob(students));
  }
}
