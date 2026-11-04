trigger SeatReservationTrigger on Seat_Reservation__c(
  before insert,
  before update
) {
  new SeatReservationTriggerHandler().run();
}
