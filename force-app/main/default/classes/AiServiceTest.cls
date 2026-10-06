@IsTest
private class AiServiceTest {
  /** Returns a fixed answer and remembers what it was asked. */
  private class StubProvider implements AiService.Provider {
    String answer;
    String lastInstructions;
    String lastMessage;
    String lastModel;
    Boolean fail = false;
    StubProvider(String answer) {
      this.answer = answer;
    }
    public String complete(String model, String instructions, String message) {
      if (fail) {
        throw new AppException('Model unavailable');
      }
      lastModel = model;
      lastInstructions = instructions;
      lastMessage = message;
      return answer;
    }
  }

  private static User aiUser() {
    User u = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        u.Id,
        new List<String>{ 'KEM_AI_User' }
      );
    }
    return u;
  }

  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Name = 'AI Branch';
      branch.Branch_Code__c = 'AI-01';
      branch.City__c = 'Bengaluru';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('AI Maths');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Monthly',
        Amount__c = 2500,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(Id = offering.Id, Name = 'AI Maths Saturday');
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      enquiry.FirstName = 'Kavya';
      enquiry.Interested_Course__c = course.Id;
      enquiry.Description = 'Wants weekend classes';
      insert enquiry;
      Account learner = PersonAccountService.buildPerson(
        'Ananya',
        'Ai' + Crypto.getRandomInteger(),
        'ananya.ai@example.com',
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Database.update(
        new CourseOfferingParticipant(
          Id = enrolmentId,
          Attendance_Rate__c = 92,
          Course_Score__c = 88.5,
          Course_Grade__c = 'A'
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private static Lead enquiry() {
    return [SELECT Id FROM Lead WHERE FirstName = 'Kavya' LIMIT 1];
  }

  private static CourseOfferingParticipant enrolment() {
    return [
      SELECT Id, ParticipantAccountId, CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE CourseOffering.Name = 'AI Maths Saturday'
    ];
  }

  @IsTest
  static void enquiryReplyIsGroundedAndLogged() {
    StubProvider stub = new StubProvider(
      'Dear Ravi, thank you for your enquiry.'
    );
    AiService.testProvider = stub;
    System.runAs(aiUser()) {
      Test.startTest();
      AiService.Result result = AiController.draftEnquiryReply(
        enquiry().Id,
        'Mention the trial'
      );
      Test.stopTest();
      Assert.isTrue(result.ok, 'Generated');
      Assert.areEqual('Enquiry Reply', result.feature, 'Feature');
      Assert.areEqual(AiService.DEFAULT_MODEL, stub.lastModel, 'Default model');
      Assert.isTrue(stub.lastMessage.contains('AI Maths'), 'Course given');
      Assert.isTrue(
        stub.lastMessage.contains('2,500') || stub.lastMessage.contains('2500'),
        'Price given: ' + stub.lastMessage
      );
      Assert.isTrue(
        stub.lastMessage.contains('AI Maths Saturday'),
        'Upcoming class given'
      );
      Assert.isTrue(
        stub.lastMessage.contains('Wants weekend classes'),
        'Enquiry notes given'
      );
      Assert.isTrue(
        stub.lastMessage.contains('Mention the trial'),
        'Counsellor note'
      );
      Assert.isTrue(
        stub.lastInstructions.contains('Never invent'),
        'Grounding rule'
      );
      Assert.isTrue(
        stub.lastInstructions.contains('under 180 words'),
        'Word limit'
      );
      AI_Interaction__c log = [
        SELECT
          Feature__c,
          Prompt_Name__c,
          Prompt_Version__c,
          Status__c,
          Outcome__c,
          Record_Id__c,
          Response__c,
          Branch__c
        FROM AI_Interaction__c
        WHERE Id = :result.interactionId
      ];
      Assert.areEqual('Succeeded', log.Status__c, 'Logged');
      Assert.areEqual('Pending Review', log.Outcome__c, 'Awaiting review');
      Assert.areEqual('Enquiry_Reply', log.Prompt_Name__c, 'Prompt');
      Assert.areEqual(enquiry().Id, log.Record_Id__c, 'Record');
      Assert.isNotNull(log.Branch__c, 'Branch');

      AiController.recordEnquiryReply(
        enquiry().Id,
        'Dear Ravi, thank you for your enquiry. See you Saturday.',
        result.interactionId
      );
      AI_Interaction__c reviewed = [
        SELECT Outcome__c, Edit_Ratio__c, Minutes_Saved__c, Reviewed_By__c
        FROM AI_Interaction__c
        WHERE Id = :result.interactionId
      ];
      Assert.areEqual('Edited', reviewed.Outcome__c, 'Edited before sending');
      Assert.isTrue(
        reviewed.Edit_Ratio__c > 0 && reviewed.Edit_Ratio__c < 100,
        'Edit share ' + reviewed.Edit_Ratio__c
      );
      Assert.isTrue(
        reviewed.Minutes_Saved__c > 0 && reviewed.Minutes_Saved__c < 4,
        'Minutes scaled by edits'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Task
          WHERE WhoId = :enquiry().Id AND Subject = 'Email reply (AI-assisted)'
        ],
        'Reply logged'
      );
    }
  }

  @IsTest
  static void accessControls() {
    AiService.testProvider = new StubProvider('x');
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      Assert.isFalse(AiController.isAvailable(null), 'No KEM AI User');
      try {
        AiService.assertAllowed('Enquiry Reply');
        Assert.fail('No permission');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('KEM AI User'), e.getMessage());
      }
    }
    System.runAs(aiUser()) {
      Assert.isTrue(AiController.isAvailable('Policy Q&A'), 'Available');
      AppSettings.overrides.put(
        'AI_Disabled_Features',
        'Enquiry Reply, Record Summary'
      );
      Assert.isFalse(AiService.featureEnabled('Enquiry Reply'), 'Feature off');
      Assert.isTrue(
        AiService.featureEnabled('Policy Q&A'),
        'Other features on'
      );
      try {
        AiController.draftEnquiryReply(enquiry().Id, null);
        Assert.fail('Feature off');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('switched off'), e.getMessage());
      }
      AppSettings.overrides.put('AI_Enabled', 'Off');
      Assert.isFalse(AiController.isAvailable(null), 'Kill switch');
      try {
        AiService.assertAllowed('Policy Q&A');
        Assert.fail('Kill switch');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('institution'), e.getMessage());
      }
    }
  }

  @IsTest
  static void modelFailureIsLoggedAndReported() {
    StubProvider stub = new StubProvider('x');
    stub.fail = true;
    AiService.testProvider = stub;
    System.runAs(aiUser()) {
      try {
        AiController.summarise(enquiry().Id);
        Assert.fail('Model failed');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('could not answer'),
          e.getMessage()
        );
      }
      AiService.Result r = AiService.generate(
        'Record_Summary',
        new Map<String, String>(),
        null,
        null
      );
      Assert.isFalse(r.ok, 'Failed');
      Assert.areEqual(
        'Failed',
        [SELECT Status__c FROM AI_Interaction__c WHERE Id = :r.interactionId]
        .Status__c,
        'Logged as failed'
      );
    }
  }

  @IsTest
  static void summariesForEachRecordType() {
    StubProvider stub = new StubProvider('- Point one\n- Point two');
    AiService.testProvider = stub;
    CourseOfferingParticipant e = enrolment();
    Id branchId = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'AI-01'].Id;
    System.runAs(aiUser()) {
      Test.startTest();
      AiController.summarise(enquiry().Id);
      Assert.isTrue(
        stub.lastMessage.contains('Record type: enquiry'),
        'Enquiry'
      );
      AiController.summarise(e.CourseOfferingId);
      Assert.isTrue(
        stub.lastMessage.contains('Record type: class') &&
        stub.lastMessage.contains('Ananya'),
        'Class with learners'
      );
      AiController.summarise(branchId);
      Assert.isTrue(
        stub.lastMessage.contains('branch daily brief for AI Branch'),
        'Branch brief'
      );
      AiController.summarise(e.ParticipantAccountId);
      Assert.isTrue(
        stub.lastMessage.contains('attendance 92%') &&
        stub.lastMessage.contains('grade A'),
        'Learner progress'
      );
      try {
        AiController.summarise(UserInfo.getUserId());
        Assert.fail('Unsupported');
      } catch (AuraHandledException ex) {
        Assert.isTrue(
          ex.getMessage().contains('not available'),
          ex.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void reportCommentDraftedAndSaved() {
    StubProvider stub = new StubProvider('Ananya has made strong progress.');
    AiService.testProvider = stub;
    CourseOfferingParticipant e = enrolment();
    System.runAs(aiUser()) {
      Test.startTest();
      List<AiAssistantService.CommentLearner> learners = AiController.classLearners(
        e.CourseOfferingId
      );
      Assert.areEqual(1, learners.size(), 'Learner listed');
      AiService.Result r = AiController.reportComment(e.Id);
      Assert.isTrue(
        stub.lastMessage.contains('Course score: 88.5%'),
        'Score given'
      );
      AiController.useReportComment(
        e.Id,
        'Ananya has made strong progress this term.',
        r.interactionId
      );
      Test.stopTest();
    }
    Assert.areEqual(
      'Ananya has made strong progress this term.',
      [SELECT Report_Comment__c FROM CourseOfferingParticipant WHERE Id = :e.Id]
      .Report_Comment__c,
      'Comment saved'
    );
  }

  @IsTest
  static void policyAnswersOnlyFromKnowledge() {
    StubProvider stub = new StubProvider(
      '```json\n{"answer": "Someone other than the requester must approve refunds above the limit.", "sources": ["Refunds and credit notes", "Invented article"], "confident": true}\n```'
    );
    AiService.testProvider = stub;
    System.runAs(aiUser()) {
      AiAssistantService.Answer answer = AiController.askPolicy(
        'Who approves a refund I requested?'
      );
      Assert.isTrue(answer.answer.contains('Someone other'), answer.answer);
      Assert.areEqual(
        new List<String>{ 'Refunds and credit notes' },
        answer.sources,
        'Only provided articles cited'
      );
      Assert.isTrue(answer.confident, 'Confident');
      Assert.isTrue(
        stub.lastMessage.contains('[Refunds and credit notes]'),
        'Article given'
      );
      Assert.isFalse(
        stub.lastMessage.contains('{{Setting:'),
        'Settings rendered'
      );

      AiAssistantService.Answer none = AiAssistantService.askPolicy(
        'zzzz qqqq xxxx'
      );
      Assert.isFalse(none.confident, 'Nothing found');
      Assert.isTrue(none.answer.contains('could not find'), none.answer);
      try {
        AiController.askPolicy('hi');
        Assert.fail('Too short');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('few words'), e.getMessage());
      }
      stub.answer = 'Plain text answer';
      AiAssistantService.Answer plain = AiAssistantService.askPolicy(
        'How long is a library loan?'
      );
      Assert.areEqual(
        'Plain text answer',
        plain.answer,
        'Non-JSON answer shown'
      );
      Assert.isFalse(plain.confident, 'Not confident without sources');
    }
  }

  @IsTest
  static void knowledgeRankingAndSettings() {
    List<AI_Knowledge__mdt> hits = AiKnowledge.retrieve(
      'library books late fine',
      2
    );
    Assert.areEqual('Library', hits[0].MasterLabel, 'Library first');
    AppSettings.overrides.put('Library_Daily_Fine', '7');
    Assert.isTrue(
      AiKnowledge.render(hits[0].Body__c).contains('fined 7 per day'),
      'Live setting'
    );
    Assert.isTrue(
      AiKnowledge.retrieve('the and for', 3).isEmpty(),
      'Stop words only'
    );
  }

  @IsTest
  static void reviewRulesAndEditRatio() {
    AiService.testProvider = new StubProvider('one two three four');
    System.runAs(aiUser()) {
      AiService.Result r = AiService.generate(
        'Record_Summary',
        new Map<String, String>{ 'Facts' => 'x' },
        null,
        null
      );
      AiController.review(
        r.interactionId,
        'Accepted',
        'one two three four',
        5,
        'Great'
      );
      AI_Interaction__c row = [
        SELECT Outcome__c, Edit_Ratio__c, Rating__c, Minutes_Saved__c
        FROM AI_Interaction__c
        WHERE Id = :r.interactionId
      ];
      Assert.areEqual('Accepted', row.Outcome__c, 'Unchanged = accepted');
      Assert.areEqual(0, row.Edit_Ratio__c, 'No edits');
      Assert.areEqual(2.0, row.Minutes_Saved__c, 'Full minutes for the prompt');
      Assert.areEqual(5, row.Rating__c, 'Rating');
      try {
        AiController.review(r.interactionId, 'Maybe', null, null, null);
        Assert.fail('Bad outcome');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Choose'), e.getMessage());
      }
      try {
        AiService.review(r.interactionId, 'Accepted', null, 9, null);
        Assert.fail('Bad rating');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('between 1 and 5'),
          e.getMessage()
        );
      }
    }
    Assert.areEqual(
      0,
      AiService.editRatio('a b c', 'A B  C'),
      'Case and spacing ignored'
    );
    Assert.areEqual(
      50.0,
      AiService.editRatio('a b c d', 'a b x y'),
      'Two of four changed'
    );
    Assert.areEqual(100, AiService.editRatio('a', 'b c d e'), 'Rewritten');
    Assert.areEqual(
      'Hi Ravi, ',
      AiService.render(
        'Hi {{Name}}, {{Unknown}}',
        new Map<String, String>{ 'Name' => 'Ravi' }
      ),
      'Unknown tokens removed'
    );
  }

  @IsTest
  static void evaluationAndConsole() {
    AiService.testProvider = new StubProvider(
      '{"answer": "Someone other than the requester; I could not find more. false", "sources": ["Refunds and credit notes"], "confident": false}'
    );
    System.runAs(aiUser()) {
      Test.startTest();
      AiEvaluationService.RunSummary run = AiController.runEvaluation();
      Test.stopTest();
      Assert.isTrue(run.cases >= 7, 'Every case ran: ' + run.cases);
      Assert.isTrue(
        run.passed >= 1 && run.passed < run.cases,
        'Some pass, some fail with a fixed answer: ' + run.passed
      );
      Assert.areEqual(
        run.cases,
        [SELECT COUNT() FROM AI_Evaluation__c],
        'Results stored'
      );
      Assert.areEqual(
        run.cases,
        [SELECT COUNT() FROM AI_Interaction__c],
        'Calls logged after the callouts'
      );
      AI_Interaction__c one = [SELECT Id FROM AI_Interaction__c LIMIT 1];
      AiService.review(one.Id, 'Rejected', null, 2, 'Not useful');
      AiConsoleService.Console c = AiController.getConsole(30);
      Assert.isTrue(c.enabled && c.isAdmin && c.canUse, 'Admin with AI');
      Assert.areEqual(run.cases, c.totals.calls, 'Calls counted');
      Assert.areEqual(1, c.totals.rejected, 'Rejection counted');
      Assert.areEqual(0, c.totals.acceptanceRate, 'None used');
      Assert.areEqual(1, c.users, 'One user');
      Assert.isNotNull(c.evaluation, 'Latest evaluation');
      Assert.isTrue(c.features.size() >= 4, 'Per feature');
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        AiEvaluationService.run(null);
        Assert.fail('Administrators only');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('administrators'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void jsonHelper() {
    Assert.areEqual(
      '{"a":1}',
      AiJson.strip('Here you go: ```json {"a":1} ``` thanks'),
      'Object extracted'
    );
    Assert.areEqual('[1,2]', AiJson.strip('[1,2]'), 'Array');
    Assert.areEqual('plain', AiJson.strip('plain'), 'No JSON');
    try {
      AiJson.parseObject('[1]');
      Assert.fail('Not an object');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('expected format'), e.getMessage());
    }
  }
}
