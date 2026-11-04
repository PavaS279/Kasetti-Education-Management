@IsTest
private class CollegeSeatServiceTest {
  @IsTest
  static void reserveIsIdempotentAndCapacityIsLocked() {
    Campus_Branch__c intake = intake(1, 0);
    IndividualApplication first = admission(intake, 'Regular');
    Id reservationId = CollegeSeatService.reserve(
      first.Id,
      System.now().addDays(7)
    );
    System.assertEquals(
      reservationId,
      CollegeSeatService.reserve(first.Id, System.now().addDays(7))
    );
    intake = counters(intake.Id);
    System.assertEquals(1, intake.Reserved_Regular__c);
    System.assertEquals(
      'Fee Pending',
      [SELECT College_Stage__c FROM IndividualApplication WHERE Id = :first.Id]
      .College_Stage__c
    );

    IndividualApplication second = admission(intake, 'Regular');
    try {
      CollegeSeatService.reserve(second.Id, System.now().addDays(7));
      System.assert(false, 'Expected the final intake seat to be protected.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('No regular'));
    }
    System.assertEquals(1, [SELECT COUNT() FROM Seat_Reservation__c]);
  }

  @IsTest
  static void finaliseAndReleaseMaintainCountersAndAreIdempotent() {
    Campus_Branch__c intake = intake(1, 1);
    IndividualApplication regular = admission(intake, 'Regular');
    Id regularSeat = CollegeSeatService.reserve(
      regular.Id,
      System.now().addDays(7)
    );
    CollegeSeatService.finalise(regularSeat);
    CollegeSeatService.finalise(regularSeat);
    intake = counters(intake.Id);
    System.assertEquals(0, intake.Reserved_Regular__c);
    System.assertEquals(1, intake.Finalised_Regular__c);
    CollegeSeatService.release(regularSeat, 'Student withdrew');
    CollegeSeatService.release(regularSeat, 'Student withdrew');
    intake = counters(intake.Id);
    System.assertEquals(0, intake.Finalised_Regular__c);

    IndividualApplication lateral = admission(intake, 'Lateral');
    Id lateralSeat = CollegeSeatService.reserve(
      lateral.Id,
      System.now().addDays(1)
    );
    CollegeSeatService.expire(lateralSeat);
    intake = counters(intake.Id);
    System.assertEquals(0, intake.Reserved_Lateral__c);
    Seat_Reservation__c expired = [
      SELECT Status__c, Release_Reason__c, Released_On__c, Actioned_By__c
      FROM Seat_Reservation__c
      WHERE Id = :lateralSeat
    ];
    System.assertEquals('Expired', expired.Status__c);
    System.assertEquals('Payment window expired', expired.Release_Reason__c);
    System.assertNotEquals(null, expired.Released_On__c);
    System.assertEquals(UserInfo.getUserId(), expired.Actioned_By__c);
  }

  @IsTest
  static void reconcileRepairsCounterDrift() {
    Campus_Branch__c intake = intake(2, 1);
    Id regularSeat = CollegeSeatService.reserve(
      admission(intake, 'Regular').Id,
      System.now().addDays(7)
    );
    CollegeSeatService.reserve(
      admission(intake, 'Lateral').Id,
      System.now().addDays(7)
    );
    CollegeSeatService.finalise(regularSeat);
    update new Campus_Branch__c(
      Id = intake.Id,
      Reserved_Regular__c = 0,
      Reserved_Lateral__c = 0,
      Finalised_Regular__c = 0,
      Finalised_Lateral__c = 0
    );

    CollegeSeatService.reconcile(intake.Id);

    intake = counters(intake.Id);
    System.assertEquals(0, intake.Reserved_Regular__c);
    System.assertEquals(1, intake.Reserved_Lateral__c);
    System.assertEquals(1, intake.Finalised_Regular__c);
    System.assertEquals(0, intake.Finalised_Lateral__c);
  }

  @IsTest
  static void applicationUniquenessAndStageGuardAreEnforced() {
    Campus_Branch__c intake = intake(2, 0);
    IndividualApplication admission = admission(intake, 'Regular');
    CollegeSeatService.reserve(admission.Id, System.now().addDays(7));
    Database.SaveResult duplicate = Database.insert(
      new Seat_Reservation__c(
        Campus_Branch__c = intake.Id,
        Application__c = admission.Id,
        Entry_Route__c = 'Regular',
        Status__c = 'Reserved'
      ),
      false
    );
    System.assertEquals(false, duplicate.isSuccess());
    System.assertEquals(
      StatusCode.DUPLICATE_VALUE,
      duplicate.getErrors()[0].getStatusCode()
    );
    IndividualApplication wrongStage = admission(intake, 'Regular');
    update new IndividualApplication(
      Id = wrongStage.Id,
      College_Stage__c = 'Processing'
    );
    try {
      CollegeSeatService.reserve(wrongStage.Id, System.now().addDays(7));
      System.assert(false, 'Expected stage guard.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('Ready For Decision'));
    }
    try {
      CollegeSeatService.reserve(
        admission(intake, 'Regular').Id,
        System.now().addMinutes(-1)
      );
      System.assert(false, 'Expected a future payment deadline.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('future payment deadline'));
    }
  }

  private static Campus_Branch__c intake(Integer regular, Integer lateral) {
    Learning programmeLearning = new Learning(
      Name = TestDataFactory.unique('Seat Programme'),
      Type = 'LearningProgram',
      IsActive = true
    );
    insert programmeLearning;
    LearningProgram programme = new LearningProgram(
      Name = programmeLearning.Name,
      LearningId = programmeLearning.Id,
      Programme_Code__c = 'S',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert programme;
    Branch__c campus = TestDataFactory.buildBranch();
    campus.Name = TestDataFactory.unique('Seat Campus');
    campus.Institution_Type__c = 'College';
    campus.Campus_Code__c = 'S';
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway';
    campus.Discounts_Allowed__c = false;
    insert campus;
    Learning courseLearning = new Learning(
      Name = TestDataFactory.unique('Seat Branch'),
      Type = 'LearningCourse',
      IsActive = true
    );
    insert courseLearning;
    LearningCourse branch = new LearningCourse(
      Name = courseLearning.Name,
      LearningId = courseLearning.Id,
      RecordTypeId = Schema.SObjectType.LearningCourse
        .getRecordTypeInfosByDeveloperName()
        .get('College_Branch')
        .getRecordTypeId(),
      External_ID__c = TestDataFactory.unique('SEAT-CRS'),
      Programme__c = programme.Id,
      Branch_Code__c = 'ST',
      Curriculum_Version__c = '2025'
    );
    insert branch;
    Campus_Branch__c value = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = branch.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = regular,
      Intake_Lateral__c = lateral,
      Admissions_Open__c = true
    );
    insert value;
    return [
      SELECT Id, Campus__c, Branch__c, Branch__r.Programme__c, Academic_Year__c
      FROM Campus_Branch__c
      WHERE Id = :value.Id
    ];
  }

  private static IndividualApplication admission(
    Campus_Branch__c intake,
    String route
  ) {
    Id programmeId = [
      SELECT Programme__c
      FROM LearningCourse
      WHERE Id = :intake.Branch__c
    ]
    .Programme__c;
    Account learner = PersonAccountService.buildPerson(
      'Seat',
      TestDataFactory.unique('Applicant'),
      null,
      null,
      intake.Campus__c,
      'Learner'
    );
    insert learner;
    learner = [SELECT Id, PersonContactId FROM Account WHERE Id = :learner.Id];
    IndividualApplication value = new IndividualApplication(
      Category = 'Education',
      AccountId = learner.Id,
      ContactId = learner.PersonContactId,
      Status = 'Processing',
      Branch__c = intake.Campus__c,
      Learning_Course__c = intake.Branch__c,
      Learning_Program__c = programmeId,
      Campus_Branch__c = intake.Id,
      College_Mode__c = true,
      College_Stage__c = 'Ready For Decision',
      Academic_Year__c = intake.Academic_Year__c,
      Entry_Route__c = route,
      Entry_Year_Of_Study__c = route == 'Lateral' ? 2 : 1,
      Interview_Date__c = System.now().addHours(-1),
      Interviewer__c = UserInfo.getUserId(),
      Interview_Outcome__c = 'Pass'
    );
    insert value;
    return value;
  }

  private static Campus_Branch__c counters(Id intakeId) {
    return [
      SELECT
        Id,
        Campus__c,
        Branch__c,
        Academic_Year__c,
        Reserved_Regular__c,
        Reserved_Lateral__c,
        Finalised_Regular__c,
        Finalised_Lateral__c
      FROM Campus_Branch__c
      WHERE Id = :intakeId
    ];
  }
}
