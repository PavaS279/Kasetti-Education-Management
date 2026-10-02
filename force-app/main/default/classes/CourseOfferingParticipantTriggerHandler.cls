/**
 * Class enrolment rules: governed participation status transitions and seat
 * recount whenever a seat may have been taken or released.
 */
public with sharing class CourseOfferingParticipantTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      CourseOfferingParticipant.ParticipationStatus
    );
  }

  protected override void afterInsert(List<SObject> newRecords) {
    SeatService.recalculate(offeringIds(newRecords));
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    List<SObject> changed = changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{
        CourseOfferingParticipant.ParticipationStatus,
        CourseOfferingParticipant.CourseOfferingId
      }
    );
    Set<Id> ids = offeringIds(changed);
    for (SObject record : changed) {
      ids.add(
        ((CourseOfferingParticipant) oldMap.get(record.Id)).CourseOfferingId
      );
    }
    SeatService.recalculate(ids);
  }

  protected override void afterDelete(List<SObject> oldRecords) {
    SeatService.recalculate(offeringIds(oldRecords));
  }

  private static Set<Id> offeringIds(List<SObject> records) {
    Set<Id> ids = new Set<Id>();
    for (
      CourseOfferingParticipant participant : (List<CourseOfferingParticipant>) records
    ) {
      ids.add(participant.CourseOfferingId);
    }
    return ids;
  }
}
