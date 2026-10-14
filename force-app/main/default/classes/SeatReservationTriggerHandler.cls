public inherited sharing class SeatReservationTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    stamp(newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    for (SObject record : newRecords) {
      Seat_Reservation__c value = (Seat_Reservation__c) record;
      Seat_Reservation__c oldValue = (Seat_Reservation__c) oldMap.get(value.Id);
      if (value.Application__c != oldValue.Application__c) {
        value.Application__c.addError(
          'The admission on a seat reservation cannot be changed.'
        );
      }
    }
    stamp(newRecords);
  }

  private static void stamp(List<SObject> records) {
    for (SObject record : records) {
      Seat_Reservation__c value = (Seat_Reservation__c) record;
      value.Application_Key__c = String.valueOf(value.Application__c);
    }
  }
}
