/**
 * Phase 2 completion condition: exceptions and recurring operations work
 * reliably. One family — a fee-paying guardian with two children — goes
 * through waitlists, recurring billing, overpayment credit, instalments,
 * teacher cover, grading and the portal, with notifications at each step.
 */
@IsTest
private class Phase2JourneyTest {
  /**
   * Branch with two teachers; a monthly course (admission 1,000 one-time +
   * tuition 2,000 monthly, 18% tax); class A (one seat, taught by teacher 1,
   * started a week ago, a session tomorrow) and class B (five seats). Guardian
   * Gauri (fee payer, email, portal access) with children Lata (enrolled in
   * class A) and Manu.
   */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    User teacher1 = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    User teacher2 = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      TestDataFactory.assignToBranch(teacher1.Id, branch.Id, 'Teacher');
      TestDataFactory.assignToBranch(teacher2.Id, branch.Id, 'Teacher');
      LearningCourse course = TestDataFactory.createCourse('Journey Science');
      insert new List<Fee_Price__c>{
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Admission',
          Billing_Frequency__c = 'One-time',
          Amount__c = 1000,
          Effective_From__c = Date.today().addDays(-30)
        ),
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Monthly',
          Amount__c = 2000,
          Effective_From__c = Date.today().addDays(-30)
        )
      };
      CourseOffering classA = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        1
      );
      CourseOffering classB = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        5
      );
      update new List<CourseOffering>{
        new CourseOffering(
          Id = classA.Id,
          Name = 'Journey A',
          Teacher_User__c = teacher1.Id
        ),
        new CourseOffering(
          Id = classB.Id,
          Name = 'Journey B',
          Teacher_User__c = teacher2.Id
        )
      };
      List<Account> people = new List<Account>{
        PersonAccountService.buildPerson(
          'Gauri',
          'Family' + Crypto.getRandomInteger(),
          'gauri.family@example.com',
          null,
          branch.Id,
          'Guardian'
        ),
        PersonAccountService.buildPerson(
          'Lata',
          'Family' + Crypto.getRandomInteger(),
          null,
          null,
          branch.Id,
          'Learner'
        ),
        PersonAccountService.buildPerson(
          'Manu',
          'Family' + Crypto.getRandomInteger(),
          null,
          null,
          branch.Id,
          'Learner'
        )
      };
      insert people;
      Map<Id, Account> byId = new Map<Id, Account>(
        [SELECT Id, PersonContactId FROM Account WHERE Id IN :people]
      );
      List<GuardianRelationshipService.GuardianLink> links = new List<GuardianRelationshipService.GuardianLink>();
      for (Integer i = 1; i <= 2; i++) {
        GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
        link.guardianContactId = byId.get(people[0].Id).PersonContactId;
        link.learnerContactId = byId.get(people[i].Id).PersonContactId;
        link.relationship = 'Mother';
        links.add(link);
      }
      GuardianRelationshipService.link(links);
      enrol(people[1].Id, classA.Id);
      insert new Class_Session__c(
        Course_Offering__c = classA.Id,
        Branch__c = branch.Id,
        Teacher_User__c = teacher1.Id,
        Start__c = Datetime.now().addDays(1),
        End__c = Datetime.now().addDays(1).addHours(1),
        Status__c = 'Scheduled'
      );
    }
  }

  private static Id enrol(Id learnerAccountId, Id offeringId) {
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = learnerAccountId;
    request.offeringId = offeringId;
    return EnrolmentService.enrol(request).enrolmentId;
  }

  private static Account person(String firstName) {
    return [
      SELECT Id, PersonContactId
      FROM Account
      WHERE FirstName = :firstName AND LastName LIKE 'Family%'
    ];
  }

  private static CourseOffering cls(String name) {
    return [
      SELECT Id, Class_Status__c, Teacher_User__c
      FROM CourseOffering
      WHERE Name = :name
    ];
  }

  private static Id enrolmentOf(String firstName, String className) {
    return [
      SELECT Id
      FROM CourseOfferingParticipant
      WHERE
        ParticipantContact.FirstName = :firstName
        AND CourseOffering.Name = :className
        AND ParticipationStatus = 'Enrolled'
    ]
    .Id;
  }

  private static Set<String> eventsFor(Id contactId) {
    Set<String> events = new Set<String>();
    for (Message__c m : [
      SELECT Event__c
      FROM Message__c
      WHERE Recipient__c = :contactId AND Channel__c = 'Portal'
    ]) {
      events.add(m.Event__c);
    }
    return events;
  }

  @IsTest
  static void freedSeatGoesToTheWaitlistAndTheFamilyIsTold() {
    Account gauri = person('Gauri');
    Account manu = person('Manu');
    CourseOffering classA = cls('Journey A');
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      Assert.areEqual(
        'Full',
        classA.Class_Status__c,
        'One seat, taken by Lata'
      );
      WaitlistService.JoinRequest joinRequest = new WaitlistService.JoinRequest();
      joinRequest.learnerAccountId = manu.Id;
      joinRequest.offeringId = classA.Id;
      Id entryId = WaitlistService.joinRequest(joinRequest);

      EnrolmentService.withdraw(
        enrolmentOf('Lata', 'Journey A'),
        'Moving to weekend batch',
        null
      );
      Waitlist_Entry__c offered = [
        SELECT Status__c, Offer_Expires__c
        FROM Waitlist_Entry__c
        WHERE Id = :entryId
      ];
      Assert.areEqual('Offered', offered.Status__c, 'Seat held for Manu');
      Assert.isTrue(
        eventsFor(gauri.PersonContactId).contains('Waitlist_Offer'),
        'Gauri is told about the seat'
      );
      Id enrolled = WaitlistService.accept(entryId);
      Assert.isNotNull(enrolled, 'Manu enrolled from the waitlist');
      Assert.areEqual('Full', cls('Journey A').Class_Status__c, 'Full again');
      Test.stopTest();
    }
  }

  @IsTest
  static void billingCreditRecurringAndInstalments() {
    Account gauri = person('Gauri');
    Account lata = person('Lata');
    Account manu = person('Manu');
    Id lataEnrolment = enrolmentOf('Lata', 'Journey A');
    Date start = [
      SELECT StartDate
      FROM CourseOfferingParticipant
      WHERE Id = :lataEnrolment
    ]
    .StartDate;
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      Id first = BillingService.createInvoice(lataEnrolment, true);
      Assert.areEqual(
        3540,
        [SELECT Total__c FROM Student_Invoice__c WHERE Id = :first].Total__c,
        'Admission 1,180 + first month 2,360'
      );
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = first;
      payment.amount = 4040;
      payment.method = 'UPI';
      BillingService.PaymentResult paid = BillingService.recordPayment(payment);
      Assert.areEqual(
        'Exception',
        paid.reconciliationStatus,
        'Overpaid by 500'
      );
      Id creditId = CreditService.holdOverpayment(paid.paymentId);

      Id manuEnrolment = enrol(manu.Id, cls('Journey B').Id);
      Id second = BillingService.createInvoice(manuEnrolment, true);
      Assert.areEqual(
        500,
        [SELECT Amount_Paid__c FROM Student_Invoice__c WHERE Id = :second]
        .Amount_Paid__c,
        'Credit applied to the sibling invoice'
      );
      Assert.areEqual(
        'Used',
        [SELECT Status__c FROM Credit_Note__c WHERE Id = :creditId].Status__c,
        'Credit used up'
      );
      Test.stopTest();

      // The nightly job's work for next month, then an instalment plan.
      Id next = BillingService.billDuePeriods(
        lataEnrolment,
        start.addMonths(1)
      );
      Assert.areEqual(
        2360,
        [SELECT Total__c FROM Student_Invoice__c WHERE Id = :next].Total__c,
        'Second month'
      );
      BillingService.PlanRequest plan = new BillingService.PlanRequest();
      plan.invoiceId = second;
      plan.count = 2;
      plan.firstDueDate = Date.today().addDays(10);
      BillingService.createPlan(plan);

      PortalService.Home home = PortalService.homeFor(gauri.PersonContactId);
      Assert.areEqual(2, home.learners.size(), 'Both children');
      Assert.areEqual(
        2360 + 3040,
        home.totalDue,
        'Next month for Lata + Manu after credit'
      );
      Set<String> events = eventsFor(gauri.PersonContactId);
      Assert.isTrue(events.contains('Invoice_Issued'), 'Invoices notified');
      Assert.isTrue(events.contains('Payment_Received'), 'Payment notified');
      PortalService.LearnerDetail manuView = PortalService.learnerFor(
        gauri.PersonContactId,
        manu.PersonContactId
      );
      Assert.areEqual(
        2,
        manuView.invoices[0].instalments.size(),
        'Instalments visible'
      );
      Assert.isFalse(
        PortalService.learnerFor(gauri.PersonContactId, lata.PersonContactId)
          .invoices.isEmpty(),
        'Lata invoices visible'
      );
    }
  }

  @IsTest
  static void coverGradingAndReportCards() {
    Account gauri = person('Gauri');
    Account lata = person('Lata');
    CourseOffering classA = cls('Journey A');
    Id teacher2 = cls('Journey B').Teacher_User__c;
    Class_Session__c session = [
      SELECT Id
      FROM Class_Session__c
      WHERE Course_Offering__c = :classA.Id
    ];
    Id absenceId;
    System.runAs(new User(Id = classA.Teacher_User__c)) {
      CoverService.AbsenceRequest absence = new CoverService.AbsenceRequest();
      absence.startAt = Datetime.now();
      absence.endAt = Datetime.now().addDays(2);
      absence.reason = 'Sick Leave';
      absenceId = CoverService.recordAbsence(absence);
    }
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      CoverService.CoverDesk desk = CoverService.desk();
      Assert.areEqual(1, desk.uncovered.size(), 'Tomorrow needs cover');
      Assert.areEqual(
        teacher2,
        desk.uncovered[0].candidates[0].userId,
        'Teacher 2 suggested'
      );
      CoverService.assignCover(session.Id, teacher2, 'Covering');
      Assert.areEqual(
        'Covered',
        [SELECT Status__c FROM Staff_Absence__c WHERE Id = :absenceId]
        .Status__c,
        'Absence covered'
      );
      Test.stopTest();
    }
    System.runAs(new User(Id = classA.Teacher_User__c)) {
      Course_Assessment__c quiz = new Course_Assessment__c(
        Name = 'Journey quiz',
        Course_Offering__c = classA.Id,
        Assessment_Type__c = 'Quiz',
        Max_Score__c = 20,
        Assessment_Date__c = Date.today()
      );
      Database.insert(quiz, AccessLevel.SYSTEM_MODE);
      AssessmentService.Gradebook book = AssessmentService.getGradebook(
        quiz.Id
      );
      book.rows[0].score = 17;
      AssessmentService.saveResults(quiz.Id, book.rows);
      AssessmentService.publish(quiz.Id);
      DocumentService.suppressJobs = true;
      GradingService.finalise(classA.Id);
      Id lataEnrolment = enrolmentOf('Lata', 'Journey A');
      new DocumentService.Job(
          new Set<Id>{ lataEnrolment },
          DocumentService.REPORT_CARD
        )
        .execute(null);
    }
    PortalService.LearnerDetail view = PortalService.learnerFor(
      gauri.PersonContactId,
      lata.PersonContactId
    );
    Assert.areEqual('A', view.grades[0].grade, '17/20 = 85%');
    Assert.areEqual('Final', view.grades[0].status, 'Final');
    Assert.isNotNull(
      view.grades[0].reportCardVersionId,
      'Report card in the portal'
    );
    Assert.isTrue(
      eventsFor(gauri.PersonContactId).contains('Report_Card_Ready'),
      'Gauri told the report card is ready'
    );
  }
}
