/**
 * Phase 4 completion condition: measured benefit with controlled access and
 * review. A referred family is answered with an AI-drafted reply that a
 * counsellor reviews, converts, enrols, rides the bus (billed monthly) and
 * sits an exam with a hall ticket; the referrer is rewarded; the forecast
 * sees the pipeline; and the AI console reports the measured use.
 */
@IsTest
private class Phase4JourneyTest {
  private class StubProvider implements AiService.Provider {
    public String complete(String model, String instructions, String message) {
      if (instructions.contains('JSON')) {
        return '{"answer": "Invoices are due in 14 days.", "sources": ["Fees and invoices"], "confident": true}';
      }
      return 'Dear Lata,\nThank you for asking about Journey Robotics. Classes start soon.\nKasetti';
    }
  }

  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Name = 'Phase Four Centre';
      branch.Branch_Code__c = 'P4-01';
      insert branch;
      TestDataFactory.createRoom(branch.Id, 20);
      LearningCourse course = TestDataFactory.createCourse('Journey Robotics');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Monthly',
        Amount__c = 3000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(
        Id = offering.Id,
        Name = 'Journey Robotics Sat'
      );
      insert PersonAccountService.buildPerson(
        'Priya',
        'Referrer',
        'priya.p4@example.com',
        null,
        branch.Id,
        'Guardian'
      );
      Transport_Route__c route = new Transport_Route__c(
        Name = 'P4 Route',
        Route_Code__c = 'P4-R1',
        Branch__c = branch.Id,
        Capacity__c = 10,
        Monthly_Fee__c = 900
      );
      insert route;
      insert new Transport_Stop__c(
        Route__c = route.Id,
        Name = 'Lake Gate',
        Sequence__c = 1,
        Pickup_Time__c = '07:30'
      );
    }
  }

  /** This test's administrator, with KEM AI User. */
  private static User aiAdmin() {
    User u = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        u.Id,
        new List<String>{ 'KEM_AI_User' }
      );
    }
    return u;
  }

  private static Branch__c branch() {
    return [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'P4-01'];
  }

  private static CourseOffering offering() {
    return [SELECT Id FROM CourseOffering WHERE Name = 'Journey Robotics Sat'];
  }

  @IsTest
  static void referredFamilyIsAnsweredEnrolledAndBilledForTransport() {
    AiService.testProvider = new StubProvider();
    System.runAs(aiAdmin()) {
      // 1. A family enquires with a referral code.
      String code = ReferralService.codeFor(
        [
          SELECT Id
          FROM Account
          WHERE FirstName = 'Priya' AND LastName = 'Referrer'
        ]
        .Id
      );
      Lead enquiry = TestDataFactory.buildEnquiry(branch().Id);
      enquiry.FirstName = 'Meera';
      enquiry.Guardian_First_Name__c = 'Lata';
      enquiry.Interested_Course__c = [
        SELECT LearningCourseId
        FROM CourseOffering
        WHERE Id = :offering().Id
      ]
      .LearningCourseId;
      enquiry.Referral_Code__c = code.toLowerCase();
      insert enquiry;
      Assert.areEqual(
        'Referral',
        [SELECT Enquiry_Channel__c FROM Lead WHERE Id = :enquiry.Id]
        .Enquiry_Channel__c,
        'Referred'
      );

      // 2. Einstein drafts the reply; the counsellor edits and records it.
      AiService.Result draft = AiController.draftEnquiryReply(
        enquiry.Id,
        'Offer a trial'
      );
      Assert.isTrue(draft.ok, 'Draft');
      AiController.recordEnquiryReply(
        enquiry.Id,
        draft.text + '\nSee you on Saturday.',
        draft.interactionId
      );
      Assert.areEqual(
        'Edited',
        [
          SELECT Outcome__c
          FROM AI_Interaction__c
          WHERE Id = :draft.interactionId
        ]
        .Outcome__c,
        'Reviewed'
      );
      AiAssistantService.Answer answer = AiController.askPolicy(
        'How long do families have to pay an invoice?'
      );
      Assert.isTrue(
        answer.confident && answer.sources.contains('Fees and invoices'),
        'Policy answer with source'
      );

      Test.startTest();
      // 3. Conversion and enrolment complete the referral; finance rewards it.
      EnquiryConversionService.ConversionRequest conversion = new EnquiryConversionService.ConversionRequest();
      conversion.leadId = enquiry.Id;
      conversion.createGuardian = true;
      conversion.createApplication = false;
      Id learnerId = EnquiryConversionService.convert(conversion).learnerId;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learnerId;
      request.offeringId = offering().Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Referral__c referral = [
        SELECT Id, Status__c
        FROM Referral__c
        WHERE Enquiry__c = :enquiry.Id
      ];
      Assert.areEqual('Enrolled', referral.Status__c, 'Referral enrolled');
      Id credit = ReferralController.grantReward(referral.Id);
      Assert.areEqual(
        'Referral',
        [SELECT Origin__c FROM Credit_Note__c WHERE Id = :credit].Origin__c,
        'Reward credit'
      );

      // 4. Transport from today, billed with the class.
      TransportService.AssignRequest bus = new TransportService.AssignRequest();
      bus.learnerAccountId = learnerId;
      bus.routeId = [
        SELECT Id
        FROM Transport_Route__c
        WHERE Route_Code__c = 'P4-R1'
      ]
      .Id;
      bus.stopId = [SELECT Id FROM Transport_Stop__c WHERE Name = 'Lake Gate']
      .Id;
      bus.startDate = Date.today();
      TransportController.assign(bus);
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      Test.stopTest();
      List<Invoice_Line__c> lines = [
        SELECT Fee_Type__c, Line_Total__c
        FROM Invoice_Line__c
        WHERE Student_Invoice__c = :invoiceId
      ];
      Set<String> types = new Set<String>();
      for (Invoice_Line__c l : lines) {
        types.add(l.Fee_Type__c);
      }
      Assert.isTrue(
        types.contains('Tuition') && types.contains('Transport'),
        'Tuition and transport on one invoice: ' + types
      );
    }
  }

  @IsTest
  static void learnersSitAnExam() {
    System.runAs(TestDataFactory.admin()) {
      List<Account> learners = new List<Account>();
      for (String first : new List<String>{ 'Ira', 'Jai' }) {
        learners.add(
          PersonAccountService.buildPerson(
            first,
            'Examinee',
            null,
            null,
            branch().Id,
            'Learner'
          )
        );
      }
      insert learners;
      for (Account l : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = l.Id;
        request.offeringId = offering().Id;
        EnrolmentService.enrol(request);
      }
      Exam__c exam = new Exam__c(
        Name = 'P4 Term Exam',
        Exam_Code__c = 'P4-T1',
        Branch__c = branch().Id,
        Start_Date__c = Date.today().addDays(7)
      );
      insert exam;
      Exam_Paper__c paper = new Exam_Paper__c(
        Exam__c = exam.Id,
        Name = 'Robotics',
        Course_Offering__c = offering().Id,
        Paper_Date__c = Date.today().addDays(7),
        Max_Marks__c = 40,
        Weight__c = 20
      );
      insert paper;

      Test.startTest();
      Assert.areEqual(
        2,
        ExamController.registerCandidates(exam.Id).processed,
        'Candidates'
      );
      Assert.areEqual(
        2,
        ExamController.checkEligibility(exam.Id).processed,
        'Eligible'
      );
      Room__c room = [
        SELECT Id
        FROM Room__c
        WHERE Branch__c = :branch().Id
        LIMIT 1
      ];
      ExamController.allocateSeats(exam.Id, new List<Id>{ room.Id });
      Assert.areEqual(
        2,
        ExamController.issueTickets(exam.Id).processed,
        'Hall tickets'
      );
      ExamService.MarkSheet sheet = ExamController.getMarkSheet(paper.Id);
      sheet.rows[0].marks = 36;
      sheet.rows[1].marks = 22;
      ExamController.saveMarks(paper.Id, sheet.rows);
      ExamController.publishMarks(paper.Id);

      Test.stopTest();

      Assert.areEqual(
        'Results Published',
        [SELECT Status__c FROM Exam__c WHERE Id = :exam.Id].Status__c,
        'Results'
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE
            LinkedEntityId IN (
              SELECT Id
              FROM Exam_Candidate__c
              WHERE Exam__c = :exam.Id
            )
        ],
        'Hall ticket PDFs'
      );
    }
  }

  @IsTest
  static void forecastIsExplainedAndTheBenefitIsMeasured() {
    AiService.testProvider = new StubProvider();
    System.runAs(aiAdmin()) {
      Test.startTest();
      // Forecast sees the branch; Einstein explains it.
      ForecastService.Forecast f = ForecastController.getForecast(
        branch().Id,
        3
      );
      Assert.isTrue(f.showEnrolments && f.showFinance, 'Forecast figures');
      AiService.Result explained = ForecastController.explainForecast(
        branch().Id,
        3
      );
      Assert.isTrue(explained.ok, 'Explained');
      Test.stopTest();
      AiService.review(
        explained.interactionId,
        'Accepted',
        explained.text,
        5,
        null
      );
      AiConsoleService.Console console = AiController.getConsole(30);
      Assert.isTrue(console.totals.calls >= 1, 'AI use measured');
      Assert.isTrue(console.totals.minutesSaved > 0, 'Minutes saved measured');
      Assert.areEqual(1, console.users, 'One AI user');
    }
  }
}
