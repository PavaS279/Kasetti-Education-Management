/**
 * Maintains seat counts on classes (CourseOffering.Seats_Taken__c) and moves a
 * class between Open and Full as seats are taken or released. Seat counting is
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

  public static void recalculate(Set<Id> offeringIds) {
    offeringIds.remove(null);
    if (offeringIds.isEmpty()) {
      return;
    }
    Map<Id, Integer> taken = countTaken(offeringIds);
    List<CourseOffering> updates = new List<CourseOffering>();
    for (CourseOffering offering : [
      SELECT Id, EnrollmentCapacity, Seats_Taken__c, Class_Status__c
      FROM CourseOffering
      WHERE Id IN :offeringIds
      WITH SYSTEM_MODE
    ]) {
      Integer count = taken.get(offering.Id);
      CourseOffering change = new CourseOffering(
        Id = offering.Id,
        Seats_Taken__c = count
      );
      Boolean full =
        offering.EnrollmentCapacity != null &&
        count >= offering.EnrollmentCapacity;
      if (offering.Class_Status__c == 'Open' && full) {
        change.Class_Status__c = 'Full';
      } else if (offering.Class_Status__c == 'Full' && !full) {
        change.Class_Status__c = 'Open';
      }
      if (offering.Seats_Taken__c != count || change.Class_Status__c != null) {
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
