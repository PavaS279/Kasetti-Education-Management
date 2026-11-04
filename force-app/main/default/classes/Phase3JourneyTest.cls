/**
 * Phase 3 completion condition: additional centres and higher volumes are
 * supported. A new centre is opened from an existing one and runs end to
 * end: enrolment, LMS sync, invoice, online payment, ERP journal, analytics,
 * retention and library.
 */
@IsTest
private class Phase3JourneyTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      Branch__c template = TestDataFactory.buildBranch();
      template.Name = 'Koramangala';
      template.Branch_Code__c = 'KOR-01';
      template.Invoice_Prefix__c = 'KOR';
      insert template;
      Room__c room = TestDataFactory.createRoom(template.Id, 12);
      LearningCourse course = TestDataFactory.createCourse(
        'Phase Three Coding'
      );
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = template.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 2000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        template.Id,
        10
      );
      update new CourseOffering(
        Id = offering.Id,
        Name = 'Coding Koramangala Mon',
        Room__c = room.Id
      );
      insert new CourseOfferingSchedule(
        CourseOfferingId = offering.Id,
        Description = 'Mondays 17:00',
        IsMonday = true,
        StartTime = Time.newInstance(17, 0, 0, 0),
        EndTime = Time.newInstance(18, 0, 0, 0)
      );
    }
  }

  private static Branch__c newCentre() {
    return [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'HSR-01'];
  }

  /** Opens HSR Layout from Koramangala and enrols the first learner. */
  private static Id openCentreAndEnrol() {
    BranchTemplateService.CloneRequest request = new BranchTemplateService.CloneRequest();
    request.sourceBranchId = [
      SELECT Id
      FROM Branch__c
      WHERE Branch_Code__c = 'KOR-01'
    ]
    .Id;
    request.name = 'HSR Layout';
    request.code = 'HSR-01';
    request.invoicePrefix = 'HSR';
    request.includeRooms = true;
    request.includePrices = true;
    request.includeDiscounts = true;
    request.includeClosures = true;
    request.includeClasses = true;
    request.classStartDate = Date.today().addDays(-7);
    BranchTemplateService.CloneResult opened = BranchTemplateService.cloneBranch(
      request
    );
    Assert.areEqual(1, opened.classes, 'Class copied');
    CourseOffering copy = [
      SELECT Id, Name, Room__c
      FROM CourseOffering
      WHERE Branch__c = :opened.branchId
    ];
    Assert.areEqual(
      'Coding HSR Layout Mon',
      copy.Name,
      'Renamed for the centre'
    );
    Assert.isNotNull(copy.Room__c, 'Room of the new centre');
    update new CourseOffering(Id = copy.Id, Class_Status__c = 'Open');

    Account learner = PersonAccountService.buildPerson(
      'Hari',
      'Centre' + Crypto.getRandomInteger(),
      'hari.centre@example.com',
      null,
      opened.branchId,
      'Learner'
    );
    insert learner;
    EnrolmentService.EnrolmentRequest enrol = new EnrolmentService.EnrolmentRequest();
    enrol.learnerAccountId = learner.Id;
    enrol.offeringId = copy.Id;
    return EnrolmentService.enrol(enrol).enrolmentId;
  }

  @IsTest
  static void newCentreBillsOnlineAndReachesTheErp() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Test');
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      Id enrolmentId = openCentreAndEnrol();
      Id branchId = newCentre().Id;

      // LMS: the copied class and the enrolment are in the outbox.
      Set<String> lmsEvents = new Set<String>();
      for (Integration_Event__c e : [
        SELECT Event_Type__c
        FROM Integration_Event__c
        WHERE Target__c = 'LMS' AND Branch__c = :branchId
      ]) {
        lmsEvents.add(e.Event_Type__c);
      }
      Assert.isTrue(
        lmsEvents.containsAll(
          new Set<String>{ 'class.updated', 'enrolment.updated' }
        ),
        'LMS events: ' + lmsEvents
      );

      Test.startTest();
      // Invoice at the new centre's price (2,000 + 18% tax) with its own prefix.
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      Student_Invoice__c invoice = [
        SELECT Name, Total__c, Learner__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ];
      Assert.isTrue(invoice.Name.startsWith('HSR'), invoice.Name);
      Assert.areEqual(2360, invoice.Total__c, 'Copied price with tax');

      // The family starts an online payment in the portal; the gateway confirms it.
      PortalService.viewerOverride = invoice.Learner__c;
      PaymentLinkService.LinkView link = PortalController.startPayment(
        invoiceId
      );
      PaymentLinkController.simulate(link.linkId);
      Test.stopTest();

      Assert.areEqual(
        'Paid',
        [SELECT Status__c FROM Student_Invoice__c WHERE Id = :invoiceId]
        .Status__c,
        'Paid online'
      );

      // ERP: the centre's journal is balanced and holds the invoice and payment.
      FinanceExportService.Journal journal = FinanceExportService.journal(
        Date.today(),
        Date.today(),
        branchId
      );
      Assert.isTrue(journal.balanced, 'Balanced');
      Assert.areEqual(2, journal.documents, 'Invoice and payment');
      Assert.areEqual('HSR-01', journal.branchCode, 'Branch');
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Integration_Event__c
          WHERE Target__c = 'ERP' AND Branch__c = :branchId
        ],
        'ERP events: invoice issued and payment confirmed'
      );

      // Analytics and branch comparison count the new centre.
      AnalyticsService.Dashboard dashboard = AnalyticsService.dashboard(
        branchId,
        6
      );
      Assert.areEqual(2360, dashboard.invoicedTotal, 'Invoiced');
      Assert.areEqual(2360, dashboard.collectedTotal, 'Collected');
      Assert.areEqual(100.0, dashboard.collectionRate, 'Collection rate');
      Boolean listed = false;
      for (
        BranchTemplateService.BranchKpi kpi : BranchTemplateService.overview()
          .branches
      ) {
        listed |=
          kpi.code == 'HSR-01' &&
          kpi.learners == 1 &&
          kpi.activeClasses == 1;
      }
      Assert.isTrue(listed, 'New centre in the branch comparison');
    }
  }

  @IsTest
  static void newCentreRetainsLearnersAndLendsBooks() {
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      Id enrolmentId = openCentreAndEnrol();
      Id branchId = newCentre().Id;
      CourseOfferingParticipant enrolment = [
        SELECT ParticipantAccountId, ParticipantContactId
        FROM CourseOfferingParticipant
        WHERE Id = :enrolmentId
      ];

      Test.startTest();
      // Retention: poor attendance makes the learner high risk with a follow-up task.
      Database.update(
        new CourseOfferingParticipant(
          Id = enrolmentId,
          Attendance_Rate__c = 45,
          Course_Score__c = 40
        ),
        AccessLevel.SYSTEM_MODE
      );
      RetentionService.assess(new Set<Id>{ enrolmentId });
      RetentionService.Desk desk = RetentionService.desk(branchId, 'High');
      Assert.areEqual(1, desk.atRisk.size(), 'At risk');
      Assert.areEqual(
        'Follow-up Needed',
        desk.atRisk[0].status,
        'Follow-up needed'
      );
      RetentionService.recordFollowUp(enrolmentId, 'Retained', null);

      // Library: the centre lends a book; a late return is fined.
      Library_Item__c book = new Library_Item__c(
        Name = 'Clean Code for Kids',
        Item_Code__c = 'HSR-B-001',
        Branch__c = branchId,
        Copies_Total__c = 1,
        Daily_Fine__c = 5
      );
      insert book;
      Id loanId = LibraryService.issue(book.Id, enrolment.ParticipantAccountId);
      Database.update(
        new Library_Loan__c(Id = loanId, Due_On__c = Date.today().addDays(-2)),
        AccessLevel.SYSTEM_MODE
      );
      Decimal fine = LibraryService.returnLoan(loanId, 'Good');
      Test.stopTest();

      Assert.areEqual(10, fine, 'Two days late');
      Assert.areEqual(
        1,
        LibraryService.desk(branchId, null).finesDue.size(),
        'Fine on the desk'
      );
      Assert.areEqual(
        1,
        LibraryService.learnerLoans(enrolment.ParticipantContactId).size(),
        'Loan in the portal'
      );
      Assert.areEqual(
        'Retained',
        [
          SELECT Retention_Status__c
          FROM CourseOfferingParticipant
          WHERE Id = :enrolmentId
        ]
        .Retention_Status__c,
        'Outcome recorded'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Task
          WHERE
            WhatId = :enrolment.ParticipantAccountId
            AND Subject LIKE 'Retention follow-up%'
        ],
        'Follow-up task'
      );
    }
  }
}
