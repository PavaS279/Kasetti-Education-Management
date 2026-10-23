/**
 * Persona UAT for the KT College demo: the admission desk (Admissions Counsellor
 * persona + KEM College Admissions), the Dean (Academic Coordinator persona +
 * KEM College Dean) and Accounts (Finance persona) run the manager's admission
 * story end to end with only the permissions the demo users will be given.
 */
@IsTest
private class CollegePersonaTest {
  @IsTest
  static void deskDeanAndAccountsRunTheAdmissionStory() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 7);
    System.runAs(fixture.dean) {
      Admission_Rule__c rule = new Admission_Rule__c(
        Branch__c = fixture.branch.Id,
        Academic_Year__c = '2026-27',
        Entry_Route__c = 'Regular',
        Status__c = 'Draft',
        Entry_Year_Of_Study__c = 1,
        Qualifying_Level__c = 'SSLC',
        Min_Percentage__c = 60,
        Entrance_Required__c = false,
        Interview_Required__c = true
      );
      insert rule;
      AdmissionRuleService.activate(rule.Id);
      insert new Admission_Document_Rule__c(
        Academic_Year__c = '2026-27',
        Document_Type__c = 'SSLC_Marks',
        Label__c = 'SSLC marks card',
        Required__c = false,
        Sensitive_Class__c = 'Academic',
        Retain_File__c = true,
        Retention_Days__c = 365,
        Active__c = true
      );
    }
    User desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    User dean = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Academic_Coordinator',
        'KEM_Academic_Coordinator_Edu',
        'KEM_College_Dean',
        'KEM_Eligibility_Override'
      }
    );
    User accounts = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Finance', 'KEM_Finance_Edu' }
    );
    // Hands-on step in the demo guide: the desk and the Dean join the college admissions team.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id team = [
        SELECT Id
        FROM Group
        WHERE DeveloperName = 'KEM_College_Admissions_Team'
      ]
      .Id;
      insert new List<GroupMember>{
        new GroupMember(GroupId = team, UserOrGroupId = desk.Id),
        new GroupMember(GroupId = team, UserOrGroupId = dean.Id)
      };
    }
    MessageService.disabled = true;
    CollegeDocumentService.suppressStatusUpdates = true;

    Test.startTest();
    CollegeAdmissionController.Admission admission;
    System.runAs(desk) {
      CollegeAdmissionController.NewAdmission request = new CollegeAdmissionController.NewAdmission();
      request.firstName = 'Persona';
      request.lastName = TestDataFactory.unique('Student');
      request.campusBranchId = CollegeAdmissionController.getIntakes()[0].value;
      request.entryRoute = 'Regular';
      CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
      q.level = 'SSLC';
      q.percentage = 82;
      request.qualifications = new List<CollegeAdmissionController.Qualification>{
        q
      };
      request.consent = true;
      admission = CollegeAdmissionController.createAdmission(request);
      System.assert(admission.consent, 'Consent recorded with the admission');
      System.assertEquals('Eligible', admission.eligibility);
      System.assert(admission.canDesk, 'The desk verifies documents');
      System.assert(!admission.canDean, 'The desk cannot interview or admit');
      admission = CollegeAdmissionController.verifyDocument(
        admission.id,
        admission.items[0].id,
        null
      );
      admission = CollegeAdmissionController.markDocumentsVerified(
        admission.id
      );
      System.assertEquals('Documents Verified', admission.stage);
    }
    // In the org the criteria sharing rule KEM_College_Admissions_Edit shares every college
    // admission with the team (verified on the seeded admissions); Apex tests do not run
    // criteria rules, so the test adds the same share.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new IndividualApplicationShare(
        ParentId = admission.id,
        UserOrGroupId = [
          SELECT Id
          FROM Group
          WHERE DeveloperName = 'KEM_College_Admissions_Team'
        ]
        .Id,
        AccessLevel = 'Edit',
        RowCause = 'Manual'
      );
    }
    System.runAs(dean) {
      admission = CollegeAdmissionController.getAdmission(admission.id);
      System.assert(admission.canDean);
      admission = CollegeAdmissionController.scheduleInterview(
        admission.id,
        System.now().addMinutes(-1)
      );
      admission = CollegeAdmissionController.recordOutcome(
        admission.id,
        'Pass',
        'Good'
      );
      admission = CollegeAdmissionController.admit(admission.id);
      System.assertEquals('Fee Pending', admission.stage);
      System.assertNotEquals(
        null,
        CollegeAdmissionsController.getOverdue(),
        'The Dean sees the overdue list'
      );
    }
    Id invoiceId = [
      SELECT Id
      FROM Student_Invoice__c
      WHERE Programme_Enrolment__c = :admission.programmeEnrolmentId
    ]
    .Id;
    System.runAs(accounts) {
      Student_Invoice__c invoice = [
        SELECT Total__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ];
      BillingService.PaymentRequest cash = new BillingService.PaymentRequest();
      cash.invoiceId = invoiceId;
      cash.amount = invoice.Total__c;
      cash.method = 'Cash';
      cash.confirmed = true;
      try {
        BillingController.recordPayment(cash);
        System.assert(false, 'Cash is refused at a college campus');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      BillingService.PaymentRequest dd = new BillingService.PaymentRequest();
      dd.invoiceId = invoiceId;
      dd.amount = invoice.Total__c;
      dd.method = 'Demand Draft';
      dd.instrumentNumber = '004512';
      dd.instrumentBank = 'Canara Bank';
      dd.instrumentDate = Date.today();
      BillingService.PaymentResult pending = BillingController.recordPayment(
        dd
      );
      System.assertEquals('Pending', pending.status);
      BillingService.confirmPayment(pending.paymentId);
    }
    Test.stopTest();
    Programme_Enrolment__c enrolment = [
      SELECT Status__c, Roll_Number__c
      FROM Programme_Enrolment__c
      WHERE Id = :admission.programmeEnrolmentId
    ];
    System.assertEquals('Enrolled', enrolment.Status__c);
    System.assert(enrolment.Roll_Number__c.startsWith('KT26AAAD'));
  }
}
