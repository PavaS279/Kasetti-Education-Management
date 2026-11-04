/** Idempotent, lock-safe college intake reservation transitions. */
public without sharing class CollegeSeatService {
  public static Id reserve(Id applicationId, Datetime expiresOn) {
    RecordAccess.assertEditable(applicationId);
    if (expiresOn == null || expiresOn <= System.now()) {
      throw new AppException('Enter a future payment deadline.');
    }
    List<Seat_Reservation__c> existing = [
      SELECT Id
      FROM Seat_Reservation__c
      WHERE Application__c = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0].Id;
    }
    IndividualApplication admission = [
      SELECT
        College_Mode__c,
        College_Stage__c,
        Campus_Branch__c,
        Entry_Route__c,
        Interview_Outcome__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (
      !admission.College_Mode__c ||
      admission.Campus_Branch__c == null ||
      admission.College_Stage__c != 'Ready For Decision' ||
      admission.Interview_Outcome__c != 'Pass'
    ) {
      throw new AppException(
        'A passed college admission at Ready For Decision is required.'
      );
    }
    Campus_Branch__c intake = lockIntake(admission.Campus_Branch__c);
    if (!intake.Admissions_Open__c) {
      throw new AppException(
        'Admissions are closed for this campus branch and year.'
      );
    }
    Boolean lateral = admission.Entry_Route__c == 'Lateral';
    Decimal capacity = lateral
      ? intake.Intake_Lateral__c
      : intake.Intake_Regular__c;
    Decimal reserved = lateral
      ? intake.Reserved_Lateral__c
      : intake.Reserved_Regular__c;
    Decimal finalised = lateral
      ? intake.Finalised_Lateral__c
      : intake.Finalised_Regular__c;
    if (
      (capacity == null ? 0 : capacity) <=
      (reserved == null ? 0 : reserved) + (finalised == null ? 0 : finalised)
    ) {
      throw new AppException(
        'No ' + admission.Entry_Route__c.toLowerCase() + ' intake seats remain.'
      );
    }
    Seat_Reservation__c reservation = new Seat_Reservation__c(
      Campus_Branch__c = intake.Id,
      Application__c = applicationId,
      Entry_Route__c = admission.Entry_Route__c,
      Status__c = 'Reserved',
      Reserved_On__c = System.now(),
      Expires_On__c = expiresOn,
      Actioned_By__c = UserInfo.getUserId()
    );
    Database.insert(reservation, AccessLevel.SYSTEM_MODE);
    increment(intake, admission.Entry_Route__c, 1, 0);
    Database.update(intake, AccessLevel.SYSTEM_MODE);
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = 'Fee Pending'
      ),
      AccessLevel.SYSTEM_MODE
    );
    return reservation.Id;
  }

  public static void finalise(Id reservationId) {
    Seat_Reservation__c reservation = lockReservation(reservationId);
    if (reservation.Status__c == 'Finalised')
      return;
    if (reservation.Status__c != 'Reserved') {
      throw new AppException('Only a reserved seat can be finalised.');
    }
    Campus_Branch__c intake = lockIntake(reservation.Campus_Branch__c);
    increment(intake, reservation.Entry_Route__c, -1, 1);
    Database.update(intake, AccessLevel.SYSTEM_MODE);
    reservation.Status__c = 'Finalised';
    reservation.Finalised_On__c = System.now();
    reservation.Actioned_By__c = UserInfo.getUserId();
    Database.update(reservation, AccessLevel.SYSTEM_MODE);
  }

  public static void release(Id reservationId, String reason) {
    if (String.isBlank(reason))
      throw new AppException('Enter a release reason.');
    transitionOut(reservationId, 'Released', reason.trim());
  }

  public static void expire(Id reservationId) {
    transitionOut(reservationId, 'Expired', 'Payment window expired');
  }

  /** Rebuilds the denormalised counters from the reservation ledger. */
  public static void reconcile(Id intakeId) {
    Campus_Branch__c intake = lockIntake(intakeId);
    Map<String, Integer> totals = new Map<String, Integer>();
    for (AggregateResult row : [
      SELECT Entry_Route__c route, Status__c status, COUNT(Id) total
      FROM Seat_Reservation__c
      WHERE
        Campus_Branch__c = :intakeId
        AND Status__c IN ('Reserved', 'Finalised')
      WITH SYSTEM_MODE
      GROUP BY Entry_Route__c, Status__c
    ]) {
      totals.put(
        String.valueOf(row.get('route')) +
          ':' +
          String.valueOf(row.get('status')),
        Integer.valueOf(row.get('total'))
      );
    }
    intake.Reserved_Regular__c = total(totals, 'Regular:Reserved');
    intake.Reserved_Lateral__c = total(totals, 'Lateral:Reserved');
    intake.Finalised_Regular__c = total(totals, 'Regular:Finalised');
    intake.Finalised_Lateral__c = total(totals, 'Lateral:Finalised');
    Database.update(intake, AccessLevel.SYSTEM_MODE);
  }

  private static void transitionOut(
    Id reservationId,
    String target,
    String reason
  ) {
    Seat_Reservation__c reservation = lockReservation(reservationId);
    if (reservation.Status__c == target)
      return;
    if (
      reservation.Status__c != 'Reserved' &&
      reservation.Status__c != 'Finalised'
    ) {
      throw new AppException('This seat reservation is already closed.');
    }
    Campus_Branch__c intake = lockIntake(reservation.Campus_Branch__c);
    increment(
      intake,
      reservation.Entry_Route__c,
      reservation.Status__c == 'Reserved' ? -1 : 0,
      reservation.Status__c == 'Finalised' ? -1 : 0
    );
    Database.update(intake, AccessLevel.SYSTEM_MODE);
    reservation.Status__c = target;
    reservation.Released_On__c = System.now();
    reservation.Release_Reason__c = reason;
    reservation.Actioned_By__c = UserInfo.getUserId();
    Database.update(reservation, AccessLevel.SYSTEM_MODE);
  }

  private static Campus_Branch__c lockIntake(Id intakeId) {
    return [
      SELECT
        Id,
        Admissions_Open__c,
        Intake_Regular__c,
        Intake_Lateral__c,
        Reserved_Regular__c,
        Reserved_Lateral__c,
        Finalised_Regular__c,
        Finalised_Lateral__c
      FROM Campus_Branch__c
      WHERE Id = :intakeId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  private static Seat_Reservation__c lockReservation(Id reservationId) {
    return [
      SELECT Id, Campus_Branch__c, Entry_Route__c, Status__c
      FROM Seat_Reservation__c
      WHERE Id = :reservationId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  private static void increment(
    Campus_Branch__c value,
    String route,
    Integer reserved,
    Integer finalised
  ) {
    if (route == 'Lateral') {
      value.Reserved_Lateral__c =
        (value.Reserved_Lateral__c == null ? 0 : value.Reserved_Lateral__c) +
        reserved;
      value.Finalised_Lateral__c =
        (value.Finalised_Lateral__c == null ? 0 : value.Finalised_Lateral__c) +
        finalised;
    } else {
      value.Reserved_Regular__c =
        (value.Reserved_Regular__c == null ? 0 : value.Reserved_Regular__c) +
        reserved;
      value.Finalised_Regular__c =
        (value.Finalised_Regular__c == null ? 0 : value.Finalised_Regular__c) +
        finalised;
    }
  }

  private static Integer total(Map<String, Integer> totals, String key) {
    return totals.containsKey(key) ? totals.get(key) : 0;
  }
}
