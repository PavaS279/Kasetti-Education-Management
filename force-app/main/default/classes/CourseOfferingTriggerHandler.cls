/**
 * Class (CourseOffering) rules: governed class status transitions; extra
 * capacity is offered to the waitlist; a new teacher or room reaches the
 * upcoming sessions.
 */
public with sharing class CourseOfferingTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    for (CourseOffering offering : (List<CourseOffering>) newRecords) {
      if (offering.Class_Status__c == null) {
        offering.Class_Status__c = 'Planned';
      }
    }
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      CourseOffering.Class_Status__c,
      'Planned'
    );
  }

  protected override void afterInsert(List<SObject> newRecords) {
    IntegrationHooks.classes(newRecords, null);
  }

  protected override void afterUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    IntegrationHooks.classes(newRecords, oldMap);
    // Upcoming sessions follow a change of teacher or room.
    ClassSetupService.propagate((List<CourseOffering>) newRecords, oldMap);
    Set<Id> grown = new Set<Id>();
    for (CourseOffering offering : (List<CourseOffering>) newRecords) {
      Integer before = ((CourseOffering) oldMap.get(offering.Id))
        .EnrollmentCapacity;
      if (
        offering.EnrollmentCapacity != null &&
        (before == null ||
        offering.EnrollmentCapacity > before)
      ) {
        grown.add(offering.Id);
      }
    }
    if (!grown.isEmpty()) {
      SeatService.recalculate(grown);
      WaitlistService.offerNext(grown);
    }
  }
}
