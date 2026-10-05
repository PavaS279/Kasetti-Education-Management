/**
 * Maintains seat counts on classes (seats taken by enrolments, seats reserved
 * for unanswered waitlist offers, learners waiting) and moves a class between
 * Open and Full as seats are taken, reserved or released. Seat counting is
 * a system calculation, independent of the running user's visibility.
 */
public without sharing class SeatService {
  public static final Set<String> SEAT_STATUSES = new Set<String>{
    'Enrolled',
    'On Hold'
  };

  public static Map<Id, Integer> countTaken(Set<Id> offeringIds) {
    Map<Id, Integer> taken = new Map<Id, Integer>();
    for (Id offeringId : offeringIds) {
      taken.put(offeringId, 0);
    }
    for (AggregateResult row : [
      SELECT CourseOfferingId offering, COUNT(Id) total
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId IN :offeringIds
        AND ParticipationStatus IN :SEAT_STATUSES
        AND ParticipantAffiliation = 'Student'
      WITH SYSTEM_MODE
      GROUP BY CourseOfferingId
    ]) {
      taken.put((Id) row.get('offering'), (Integer) row.get('total'));
    }
    return taken;
  }

  /** Seats held for open waitlist offers, optionally ignoring one entry (the accepting learner's). */
  public static Map<Id, Integer> countReserved(
    Set<Id> offeringIds,
    Id excludeEntryId
  ) {
    Map<Id, Integer> reserved = new Map<Id, Integer>();
    for (Id offeringId : offeringIds) {
      reserved.put(offeringId, 0);
    }
    for (AggregateResult row : [
      SELECT Course_Offering__c offering, COUNT(Id) total
      FROM Waitlist_Entry__c
      WHERE
        Course_Offering__c IN :offeringIds
        AND Status__c = 'Offered'
        AND Id != :excludeEntryId
      WITH SYSTEM_MODE
      GROUP BY Course_Offering__c
    ]) {
      reserved.put((Id) row.get('offering'), (Integer) row.get('total'));
    }
    return reserved;
  }

  public static void recalculate(Set<Id> offeringIds) {
    offeringIds.remove(null);
    if (offeringIds.isEmpty()) {
      return;
    }
    Map<Id, Integer> taken = countTaken(offeringIds);
    // One aggregate for both held offers and learners waiting.
    Map<Id, Integer> reserved = new Map<Id, Integer>();
    Map<Id, Integer> waiting = new Map<Id, Integer>();
    for (Id offeringId : offeringIds) {
      reserved.put(offeringId, 0);
      waiting.put(offeringId, 0);
    }
    for (AggregateResult row : [
      SELECT Course_Offering__c offering, Status__c status, COUNT(Id) total
      FROM Waitlist_Entry__c
      WHERE
        Course_Offering__c IN :offeringIds
        AND Status__c IN ('Offered', 'Waiting')
      WITH SYSTEM_MODE
      GROUP BY Course_Offering__c, Status__c
    ]) {
      ((String) row.get('status') == 'Offered' ? reserved : waiting)
        .put((Id) row.get('offering'), (Integer) row.get('total'));
    }
    List<CourseOffering> updates = new List<CourseOffering>();
    for (CourseOffering offering : [
      SELECT
        Id,
        EnrollmentCapacity,
        Seats_Taken__c,
        Seats_Reserved__c,
        Waitlist_Count__c,
        Class_Status__c
      FROM CourseOffering
      WHERE Id IN :offeringIds
      WITH SYSTEM_MODE
    ]) {
      Integer count = taken.get(offering.Id);
      Integer held = reserved.get(offering.Id);
      Integer queued = waiting.get(offering.Id);
      CourseOffering change = new CourseOffering(
        Id = offering.Id,
        Seats_Taken__c = count,
        Seats_Reserved__c = held,
        Waitlist_Count__c = queued
      );
      Boolean full =
        offering.EnrollmentCapacity != null &&
        count + held >= offering.EnrollmentCapacity;
      if (offering.Class_Status__c == 'Open' && full) {
        change.Class_Status__c = 'Full';
      } else if (offering.Class_Status__c == 'Full' && !full) {
        change.Class_Status__c = 'Open';
      }
      if (
        offering.Seats_Taken__c != count ||
        offering.Seats_Reserved__c != held ||
        offering.Waitlist_Count__c != queued ||
        change.Class_Status__c != null
      ) {
        updates.add(change);
      }
    }
    if (!updates.isEmpty()) {
      Logger.errors(
        'SeatService.recalculate',
        Database.update(updates, false, AccessLevel.SYSTEM_MODE)
      );
    }
  }
}
