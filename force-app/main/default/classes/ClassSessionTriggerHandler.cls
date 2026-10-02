/**
 * Session rules: governed status transitions and hard teacher/room
 * double-booking prevention on create and on any time, room, or teacher change.
 */
public with sharing class ClassSessionTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    rejectConflicts((List<Class_Session__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      Class_Session__c.Status__c
    );
    List<Class_Session__c> changed = (List<Class_Session__c>) changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{
        Class_Session__c.Start__c,
        Class_Session__c.End__c,
        Class_Session__c.Room__c,
        Class_Session__c.Teacher_User__c,
        Class_Session__c.Status__c
      }
    );
    rejectConflicts(changed);
  }

  private static void rejectConflicts(List<Class_Session__c> sessions) {
    Map<Integer, List<SessionService.Conflict>> conflicts = SessionService.findConflicts(
      sessions
    );
    for (Integer index : conflicts.keySet()) {
      sessions[index].addError(conflicts.get(index)[0].message);
    }
  }
}
