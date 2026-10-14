@IsTest
private class ProgrammeEnrolmentServiceTest {
  private class Fixture {
    User dean;
    IndividualApplication admission;
    Campus_Branch__c intake;
    LearningProgram programme;
  }

  @IsTest
  static void admitCreatesLinkedProvisionalRecordsAndIsIdempotent() {
    Fixture fixture = createFixture(2, 5);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      System.assertEquals(
        enrolmentId,
        InterviewService.admit(fixture.admission.Id)
      );

      Programme_Enrolment__c enrolment = [
        SELECT
          Student__c,
          Programme__c,
          Branch__c,
          Campus__c,
          Campus_Branch__c,
          Application__c,
          Entry_Route__c,
          Entry_Year_Of_Study__c,
          Admission_Year__c,
          Academic_Year__c,
          Current_Year_Of_Study__c,
          Status__c,
          Payment_Due_By__c
        FROM Programme_Enrolment__c
        WHERE Id = :enrolmentId
      ];
      System.assertEquals(fixture.admission.AccountId, enrolment.Student__c);
      System.assertEquals(fixture.programme.Id, enrolment.Programme__c);
      System.assertEquals('Provisional', enrolment.Status__c);
      System.assertEquals(Date.today().addDays(5), enrolment.Payment_Due_By__c);
      System.assertEquals(2026, enrolment.Admission_Year__c);
      System.assertEquals(1, enrolment.Current_Year_Of_Study__c);

      Seat_Reservation__c reservation = [
        SELECT Programme_Enrolment__c, Status__c, Expires_On__c
        FROM Seat_Reservation__c
        WHERE Application__c = :fixture.admission.Id
      ];
      System.assertEquals(enrolmentId, reservation.Programme_Enrolment__c);
      System.assertEquals('Reserved', reservation.Status__c);
      System.assertEquals(
        Date.today().addDays(5),
        reservation.Expires_On__c.date()
      );
      System.assertEquals(
        'Fee Pending',
        [
          SELECT College_Stage__c
          FROM IndividualApplication
          WHERE Id = :fixture.admission.Id
        ]
        .College_Stage__c
      );
      System.assertEquals(
        1,
        [
          SELECT Reserved_Regular__c
          FROM Campus_Branch__c
          WHERE Id = :fixture.intake.Id
        ]
        .Reserved_Regular__c
      );
      System.assertEquals(1, [SELECT COUNT() FROM Programme_Enrolment__c]);
      System.assertEquals(1, [SELECT COUNT() FROM Seat_Reservation__c]);
      Student_Invoice__c invoice = [
        SELECT
          Programme_Enrolment__c,
          Year_Of_Study__c,
          Invoice_Kind__c,
          Status__c,
          Total__c
        FROM Student_Invoice__c
        WHERE Programme_Enrolment__c = :enrolmentId
      ];
      System.assertEquals('Annual', invoice.Invoice_Kind__c);
      System.assertEquals('Issued', invoice.Status__c);
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoice.Id;
      payment.amount = invoice.Total__c;
      payment.method = 'Online Gateway';
      BillingService.recordPayment(payment);
      enrolment = [
        SELECT Status__c, Roll_Number__c, Roll_Issued_On__c
        FROM Programme_Enrolment__c
        WHERE Id = :enrolmentId
      ];
      System.assertEquals('Enrolled', enrolment.Status__c);
      System.assertEquals('KT26AAAD001', enrolment.Roll_Number__c);
      System.assertEquals(Date.today(), enrolment.Roll_Issued_On__c);
      System.assertEquals(
        enrolment.Roll_Number__c,
        RollNumberService.issue(enrolmentId)
      );
      reservation = [
        SELECT Status__c
        FROM Seat_Reservation__c
        WHERE Programme_Enrolment__c = :enrolmentId
      ];
      System.assertEquals('Finalised', reservation.Status__c);
      Campus_Branch__c finalIntake = [
        SELECT Reserved_Regular__c, Finalised_Regular__c
        FROM Campus_Branch__c
        WHERE Id = :fixture.intake.Id
      ];
      System.assertEquals(0, finalIntake.Reserved_Regular__c);
      System.assertEquals(1, finalIntake.Finalised_Regular__c);
    }
  }

  @IsTest
  static void downstreamFailureRollsBackSeatAndStage() {
    Fixture fixture = createFixture(2, 7);
    System.runAs(fixture.dean) {
      Account secondStudent = PersonAccountService.buildPerson(
        'Existing',
        TestDataFactory.unique('Student'),
        null,
        null,
        fixture.admission.Branch__c,
        'Learner'
      );
      insert secondStudent;
      IndividualApplication existingApplication = application(
        secondStudent,
        fixture,
        'Fee Pending'
      );
      insert existingApplication;
      insert new Programme_Enrolment__c(
        Student__c = fixture.admission.AccountId,
        Programme__c = fixture.programme.Id,
        Branch__c = fixture.admission.Learning_Course__c,
        Campus__c = fixture.admission.Branch__c,
        Campus_Branch__c = fixture.intake.Id,
        Application__c = existingApplication.Id,
        Entry_Route__c = 'Regular',
        Entry_Year_Of_Study__c = 1,
        Admission_Year__c = 2026,
        Academic_Year__c = '2026-27',
        Current_Year_Of_Study__c = 1,
        Status__c = 'Provisional',
        Payment_Due_By__c = Date.today().addDays(7)
      );

      try {
        InterviewService.admit(fixture.admission.Id);
        System.assert(false, 'Expected the active-enrolment uniqueness guard.');
      } catch (DmlException expected) {
        System.assert(expected.getMessage().contains('DUPLICATE_VALUE'));
      }
      System.assertEquals(
        'Ready For Decision',
        [
          SELECT College_Stage__c
          FROM IndividualApplication
          WHERE Id = :fixture.admission.Id
        ]
        .College_Stage__c
      );
      System.assertEquals(
        0,
        [
          SELECT Reserved_Regular__c
          FROM Campus_Branch__c
          WHERE Id = :fixture.intake.Id
        ]
        .Reserved_Regular__c
      );
      System.assertEquals(
        0,
        [
          SELECT COUNT()
          FROM Seat_Reservation__c
          WHERE Application__c = :fixture.admission.Id
        ]
      );
    }
  }

  @IsTest
  static void admissionFeeRuleRaisesAdmissionInvoice() {
    Fixture fixture = createFixture(1, 7);
    System.runAs(fixture.dean) {
      update new LearningProgram(
        Id = fixture.programme.Id,
        Roll_Release_Rule__c = 'Admission Fee'
      );
      insert new Fee_Price__c(
        Learning_Course__c = fixture.admission.Learning_Course__c,
        Fee_Type__c = 'Admission',
        Billing_Frequency__c = 'One-time',
        Amount__c = 5000,
        Year_Of_Study__c = 1,
        Academic_Year__c = '2026-27',
        Effective_From__c = Date.today().addDays(-1)
      );

      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      Student_Invoice__c invoice = [
        SELECT Invoice_Kind__c
        FROM Student_Invoice__c
        WHERE Programme_Enrolment__c = :enrolmentId
      ];
      System.assertEquals('Admission', invoice.Invoice_Kind__c);
    }
  }

  @IsTest
  static void rejectedOrUnauthorisedAdmissionIsRefused() {
    Fixture fixture = createFixture(1, null);
    System.runAs(fixture.dean) {
      update new IndividualApplication(
        Id = fixture.admission.Id,
        Interview_Outcome__c = 'Reject'
      );
      try {
        InterviewService.admit(fixture.admission.Id);
        System.assert(false, 'Expected a passed interview.');
      } catch (AppException expected) {
        System.assert(
          expected.getMessage().contains('passed college admission')
        );
      }
    }
    User unauthorised = TestDataFactory.createUser(new List<String>());
    System.runAs(unauthorised) {
      try {
        ProgrammeEnrolmentService.admit(fixture.admission.Id);
        System.assert(false, 'Expected Dean permission.');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('permission'));
      }
    }
  }

  private static Fixture createFixture(
    Integer capacity,
    Integer paymentWindowDays
  ) {
    Fixture value = new Fixture();
    TestDataFactory.createReferenceData();
    value.dean = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Administrator',
        'KEM_Administrator_Edu',
        'KEM_College_Dean'
      }
    );
    System.runAs(value.dean) {
      Learning learning = new Learning(
        Name = TestDataFactory.unique('Admit Programme'),
        Type = 'LearningProgram',
        IsActive = true
      );
      insert learning;
      value.programme = new LearningProgram(
        Name = learning.Name,
        LearningId = learning.Id,
        Programme_Code__c = 'A',
        Duration_Years__c = 4,
        Terms_Per_Year__c = 2,
        Term_Label__c = 'Semester',
        Qualification_Level__c = 'BE',
        Roll_Release_Rule__c = 'Full Annual Invoice',
        Payment_Window_Days__c = paymentWindowDays,
        Active__c = true
      );
      insert value.programme;
      Branch__c campus = TestDataFactory.buildBranch();
      campus.Name = TestDataFactory.unique('Admit Campus');
      campus.Institution_Type__c = 'College';
      campus.Campus_Code__c = 'A';
      campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway';
      campus.Discounts_Allowed__c = false;
      insert campus;
      Learning courseLearning = new Learning(
        Name = TestDataFactory.unique('Admit Branch'),
        Type = 'LearningCourse',
        IsActive = true
      );
      insert courseLearning;
      LearningCourse branch = new LearningCourse(
        Name = courseLearning.Name,
        LearningId = courseLearning.Id,
        RecordTypeId = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName()
          .get('College_Branch')
          .getRecordTypeId(),
        External_ID__c = TestDataFactory.unique('ADMIT-CRS'),
        Programme__c = value.programme.Id,
        Branch_Code__c = 'AD',
        Curriculum_Version__c = '2025'
      );
      insert branch;
      insert new Fee_Price__c(
        Learning_Course__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Annual',
        Amount__c = 100000,
        Year_Of_Study__c = 1,
        Academic_Year__c = '2026-27',
        Effective_From__c = Date.today().addDays(-1)
      );
      value.intake = new Campus_Branch__c(
        Campus__c = campus.Id,
        Branch__c = branch.Id,
        Academic_Year__c = '2026-27',
        Intake_Regular__c = capacity,
        Intake_Lateral__c = 0,
        Admissions_Open__c = true
      );
      insert value.intake;
      Account student = PersonAccountService.buildPerson(
        'Admit',
        TestDataFactory.unique('Applicant'),
        null,
        null,
        campus.Id,
        'Learner'
      );
      insert student;
      value.admission = application(student, value, 'Ready For Decision');
      insert value.admission;
      value.admission = [
        SELECT Id, AccountId, Branch__c, Learning_Course__c
        FROM IndividualApplication
        WHERE Id = :value.admission.Id
      ];
    }
    return value;
  }

  private static IndividualApplication application(
    Account student,
    Fixture fixture,
    String collegeStage
  ) {
    student = [SELECT Id, PersonContactId FROM Account WHERE Id = :student.Id];
    Campus_Branch__c intake = [
      SELECT Campus__c, Branch__c
      FROM Campus_Branch__c
      WHERE Id = :fixture.intake.Id
    ];
    return new IndividualApplication(
      Category = 'Education',
      AccountId = student.Id,
      ContactId = student.PersonContactId,
      Status = 'Processing',
      Branch__c = intake.Campus__c,
      Learning_Course__c = intake.Branch__c,
      Learning_Program__c = fixture.programme.Id,
      Campus_Branch__c = fixture.intake.Id,
      College_Mode__c = true,
      College_Stage__c = collegeStage,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1,
      Interview_Date__c = System.now().addHours(-1),
      Interviewer__c = fixture.dean.Id,
      Interview_Outcome__c = 'Pass'
    );
  }
}
