/**
 * Trigger-side entry points of the integration outbox. They pick the records
 * whose change matters to an external system and never let an outbox failure
 * break the business transaction.
 */
public with sharing class IntegrationHooks {
  private static final List<SObjectField> CLASS_FIELDS = new List<SObjectField>{
    CourseOffering.Name,
    CourseOffering.Class_Status__c,
    CourseOffering.StartDate,
    CourseOffering.EndDate,
    CourseOffering.EnrollmentCapacity,
    CourseOffering.Teacher_User__c,
    CourseOffering.Delivery_Mode__c,
    CourseOffering.LearningCourseId
  };

  public static void classes(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    try {
      IntegrationService.classesChanged(
        changedIds(newRecords, oldMap, CLASS_FIELDS)
      );
    } catch (Exception e) {
      Logger.error('IntegrationHooks.classes', e, null);
    }
  }

  public static void enrolments(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    try {
      IntegrationService.enrolmentsChanged(
        changedIds(
          newRecords,
          oldMap,
          new List<SObjectField>{
            CourseOfferingParticipant.ParticipationStatus,
            CourseOfferingParticipant.CourseOfferingId
          }
        )
      );
    } catch (Exception e) {
      Logger.error('IntegrationHooks.enrolments', e, null);
    }
  }

  /** Records that entered the given status (inserted with it, or changed to it). */
  public static void finance(
    String eventType,
    List<SObject> newRecords,
    Map<Id, SObject> oldMap,
    SObjectField statusField,
    String status
  ) {
    try {
      List<SObject> entered = new List<SObject>();
      for (SObject row : newRecords) {
        Boolean wasAlready =
          oldMap != null &&
          oldMap.get(row.Id).get(statusField) == status;
        if (status == null || (row.get(statusField) == status && !wasAlready)) {
          entered.add(row);
        }
      }
      IntegrationService.financeDocuments(eventType, entered);
    } catch (Exception e) {
      Logger.error('IntegrationHooks.finance', e, null);
    }
  }

  private static Set<Id> changedIds(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap,
    List<SObjectField> fields
  ) {
    Set<Id> ids = new Set<Id>();
    for (SObject row : newRecords) {
      if (oldMap == null) {
        ids.add(row.Id);
        continue;
      }
      SObject old = oldMap.get(row.Id);
      for (SObjectField field : fields) {
        if (row.get(field) != old.get(field)) {
          ids.add(row.Id);
          break;
        }
      }
    }
    return ids;
  }
}
