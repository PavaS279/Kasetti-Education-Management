@IsTest
private class AgentActionsTest {
  private class StubProvider implements AiService.Provider {
    String answer;
    StubProvider(String answer) {
      this.answer = answer;
    }
    public String complete(String model, String instructions, String message) {
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
      branch.Name = 'Agent Branch';
      branch.Branch_Code__c = 'AGT-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Agent Maths');
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
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      enquiry.FirstName = 'Zubin';
      enquiry.LastName = 'Agentcase';
      enquiry.Interested_Course__c = course.Id;
      insert enquiry;
      List<Account> learners = new List<Account>();
      for (String first : new List<String>{ 'Meera', 'Mehul' }) {
        learners.add(
          PersonAccountService.buildPerson(
            first,
            'Agentlearner',
            first.toLowerCase() + '.agent@example.com',
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learners[0].Id;
      request.offeringId = offering.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Database.update(
        new CourseOfferingParticipant(
          Id = enrolmentId,
          Risk_Level__c = 'High',
          Risk_Score__c = 70,
          Risk_Reasons__c = '3 absences in a row'
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  @IsTest
  static void policyAnswerWithSources() {
    AiService.testProvider = new StubProvider(
      '{"answer": "Refunds follow the refund policy.", "sources": ["refunds and credit notes", "Made-up article"], "confident": true}'
    );
    AgentPolicyAnswer.Request r = new AgentPolicyAnswer.Request();
    r.question = 'How do refunds and credit notes work?';
    System.runAs(aiUser()) {
      // Two requests in one call: logs are held until all answers are in.
      List<AgentPolicyAnswer.Response> responses = AgentPolicyAnswer.answer(
        new List<AgentPolicyAnswer.Request>{ r, r }
      );
      Assert.areEqual(2, responses.size(), 'One answer per request');
      AgentPolicyAnswer.Response response = responses[0];
      Assert.isFalse(AiService.deferLogs, 'Logging restored');
      Assert.areEqual(
        AiService.CHANNEL_IN_APP,
        AiService.channel,
        'Channel reset'
      );
      Assert.areEqual(
        'Refunds follow the refund policy.',
        response.answer,
        'Answer'
      );
      Assert.isTrue(response.confident, 'Confident');
      Assert.areEqual(
        'Refunds and credit notes',
        response.sources,
        'Only given articles cited, with their own title'
      );
    }
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM AI_Interaction__c],
      'Both calls logged'
    );
    AI_Interaction__c row = [
      SELECT Channel__c, Outcome__c
      FROM AI_Interaction__c
      LIMIT 1
    ];
    Assert.areEqual('Agentforce', row.Channel__c, 'Logged on agent channel');
    Assert.areEqual('Not Applicable', row.Outcome__c, 'No review expected');
  }

  @IsTest
  static void learnerByNameAndAmbiguity() {
    AiService.testProvider = new StubProvider('Meera is doing well.');
    System.runAs(aiUser()) {
      AgentLearnerSummary.Request exact = new AgentLearnerSummary.Request();
      exact.learner = 'Meera Agentlearner';
      AgentLearnerSummary.Request several = new AgentLearnerSummary.Request();
      several.learner = 'Agentlearner';
      AgentLearnerSummary.Request none = new AgentLearnerSummary.Request();
      none.learner = 'Nobody Here';
      List<AgentLearnerSummary.Response> responses = AgentLearnerSummary.summarise(
        new List<AgentLearnerSummary.Request>{ exact, several, none }
      );
      Assert.areEqual('Meera is doing well.', responses[0].summary, 'Summary');
      Assert.isNotNull(responses[0].learnerId, 'Learner found');
      Assert.isTrue(
        responses[1].summary.startsWith('Several learners match'),
        responses[1].summary
      );
      Assert.isTrue(
        responses[1].summary.contains('Meera Agentlearner') &&
        responses[1].summary.contains('Mehul Agentlearner'),
        'Choices listed'
      );
      Assert.isTrue(
        responses[2].summary.startsWith('I could not find a learner'),
        responses[2].summary
      );
    }
  }

  @IsTest
  static void enquiryDraftById() {
    AiService.testProvider = new StubProvider('Dear Zubin, thank you.');
    Lead enquiry = [SELECT Id FROM Lead WHERE LastName = 'Agentcase'];
    System.runAs(aiUser()) {
      AgentEnquiryDraft.Request r = new AgentEnquiryDraft.Request();
      r.enquiry = enquiry.Id;
      r.note = 'Offer a trial';
      AgentEnquiryDraft.Response response = AgentEnquiryDraft.draft(
        new List<AgentEnquiryDraft.Request>{ r }
      )[0];
      Assert.areEqual('Dear Zubin, thank you.', response.draft, 'Draft');
      Assert.areEqual(enquiry.Id, response.enquiryId, 'Enquiry');
    }
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Task
        WHERE WhoId = :enquiry.Id AND Subject LIKE 'Email reply%'
      ],
      'Nothing sent or logged as sent'
    );
  }

  @IsTest
  static void branchBriefByCodeAndAtRiskList() {
    AiService.testProvider = new StubProvider('Agent Branch is steady.');
    System.runAs(aiUser()) {
      AgentBranchBrief.Request r = new AgentBranchBrief.Request();
      r.branch = 'agt-01';
      AgentBranchBrief.Response brief = AgentBranchBrief.brief(
        new List<AgentBranchBrief.Request>{ r }
      )[0];
      Assert.areEqual('Agent Branch is steady.', brief.briefing, 'Briefing');

      AgentAtRiskLearners.Request risk = new AgentAtRiskLearners.Request();
      risk.branch = 'Agent Branch';
      risk.level = 'High';
      AgentAtRiskLearners.Request bad = new AgentAtRiskLearners.Request();
      bad.level = 'Whatever';
      AgentAtRiskLearners.Request missing = new AgentAtRiskLearners.Request();
      missing.branch = 'No Such Branch';
      List<AgentAtRiskLearners.Response> responses = AgentAtRiskLearners.findAtRisk(
        new List<AgentAtRiskLearners.Request>{ risk, bad, missing }
      );
      Assert.areEqual(1, responses[0].high, 'High count');
      Assert.isTrue(
        responses[0].learners.contains('Meera Agentlearner') &&
        responses[0].learners.contains('3 absences in a row'),
        responses[0].learners
      );
      Assert.isTrue(
        responses[1].learners.contains('Meera Agentlearner'),
        'Unknown level means all'
      );
      Assert.isTrue(
        responses[2].learners.startsWith('I could not find a branch'),
        responses[2].learners
      );
    }
  }

  @IsTest
  static void withoutAiPermissionTheAgentIsTold() {
    AgentPolicyAnswer.Request r = new AgentPolicyAnswer.Request();
    r.question = 'How do refunds and credit notes work?';
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      AgentPolicyAnswer.Response response = AgentPolicyAnswer.answer(
        new List<AgentPolicyAnswer.Request>{ r }
      )[0];
      Assert.isTrue(response.answer.contains('KEM AI User'), response.answer);
      Assert.isFalse(response.confident, 'Not confident');
    }
  }

  @IsTest
  static void describeTruncatesLongLists() {
    List<RetentionService.AtRisk> rows = new List<RetentionService.AtRisk>();
    for (Integer i = 0; i < AgentAtRiskLearners.MAX_ROWS + 3; i++) {
      RetentionService.AtRisk row = new RetentionService.AtRisk();
      row.learner = 'Learner ' + i;
      row.className = 'Class';
      row.level = 'Medium';
      row.score = 40;
      rows.add(row);
    }
    String text = AgentAtRiskLearners.describe(rows);
    Assert.isTrue(text.contains('…and 3 more'), text);
    Assert.areEqual(
      'No learners are currently flagged at risk.',
      AgentAtRiskLearners.describe(new List<RetentionService.AtRisk>()),
      'Empty'
    );
    Assert.isTrue(
      AgentSupport.failure(new DmlException('boom')).contains('boom'),
      'Generic failure'
    );
  }
}
