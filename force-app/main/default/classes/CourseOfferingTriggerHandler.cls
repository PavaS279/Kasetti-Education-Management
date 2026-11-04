/**
 * Class (CourseOffering) rules: governed class status transitions; extra
 * capacity is offered to the waitlist; a new teacher or room reaches the
 * upcoming sessions.
 */
public with sharing class CourseOfferingTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    List<CourseOffering> offerings = (List<CourseOffering>) newRecords;
    stampCollegeSectionKey(offerings);
    for (CourseOffering offering : offerings) {
      if (offering.Class_Status__c == null) {
        offering.Class_Status__c = 'Planned';
      }
    }
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    stampCollegeSectionKey((List<CourseOffering>) newRecords);
    StatusTransitionService.validate(
      newRecords,
      oldMap,
      CourseOffering.Class_Status__c,
      'Planned'
    );
  }

  private static void stampCollegeSectionKey(List<CourseOffering> offerings) {
    Set<Id> campusBranchIds = new Set<Id>();
    for (CourseOffering offering : offerings) {
      if (offering.Campus_Branch__c != null) {
        campusBranchIds.add(offering.Campus_Branch__c);
      }
    }
    Map<Id, Campus_Branch__c> campusBranches = campusBranchIds.isEmpty()
      ? new Map<Id, Campus_Branch__c>()
      : new Map<Id, Campus_Branch__c>(
          [
            SELECT
              Id,
              Campus__c,
              Branch__c,
              Academic_Year__c,
              Branch__r.Programme__r.Duration_Years__c
            FROM Campus_Branch__c
            WHERE Id IN :campusBranchIds
            WITH SYSTEM_MODE
          ]
        );
    for (CourseOffering offering : offerings) {
      offering.Academic_Year__c = String.isBlank(offering.Academic_Year__c)
        ? null
        : offering.Academic_Year__c.trim();
      offering.Section_Code__c = String.isBlank(offering.Section_Code__c)
        ? null
        : offering.Section_Code__c.trim().toUpperCase();
      Campus_Branch__c campusBranch = campusBranches.get(
        offering.Campus_Branch__c
      );
      if (
        campusBranch != null &&
        campusBranch.Branch__c != offering.LearningCourseId
      ) {
        offering.Campus_Branch__c.addError(
          'The campus branch does not offer the section\'s college branch.'
        );
      }
      if (
        campusBranch != null &&
        campusBranch.Campus__c != offering.Branch__c
      ) {
        offering.Campus_Branch__c.addError(
          'The section campus must match the selected campus branch.'
        );
      }
      if (
        campusBranch != null &&
        campusBranch.Academic_Year__c != offering.Academic_Year__c
      ) {
        offering.Academic_Year__c.addError(
          'The section academic year must match the selected campus branch.'
        );
      }
      if (
        campusBranch?.Branch__r?.Programme__r?.Duration_Years__c != null &&
        offering.Year_Of_Study__c != null &&
        offering.Year_Of_Study__c >
        campusBranch.Branch__r.Programme__r.Duration_Years__c
      ) {
        offering.Year_Of_Study__c.addError(
          'Section year of study cannot exceed the programme duration.'
        );
      }
      offering.College_Section_Key__c = offering.Campus_Branch__c == null ||
        offering.Academic_Year__c == null ||
        offering.Year_Of_Study__c == null ||
        offering.Section_Code__c == null
        ? null
        : String.valueOf(offering.Campus_Branch__c) +
          '|' +
          offering.Academic_Year__c +
          '|' +
          String.valueOf(offering.Year_Of_Study__c) +
          '|' +
          offering.Section_Code__c;
    }
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
