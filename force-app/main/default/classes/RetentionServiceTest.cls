@IsTest
private class RetentionServiceTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'RET-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Retention Science');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        5
      );
      // The class ends in 20 days: its learners are re-enrolment candidates.
      update new CourseOffering(
        Id = offering.Id,
        EndDate = Datetime.newInstance(
          Date.today().addDays(20),
          Time.newInstance(17, 0, 0, 0)
        )
      );
      List<Account> learners = new List<Account>();
      for (Integer i = 0; i < 2; i++) {
        learners.add(
          PersonAccountService.buildPerson(
            'Risk' + i,
            'Learner' + Crypto.getRandomInteger(),
            'risk' + i + '@example.com',
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      for (Account learner : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learner.Id;
        request.offeringId = offering.Id;
        EnrolmentService.enrol(request);
      }
    }
  }

  private static List<CourseOfferingParticipant> enrolments() {
    return [
      SELECT Id, ParticipantContactId, ParticipantAccountId, CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE Branch__r.Branch_Code__c = 'RET-01'
      ORDER BY ParticipantContact.FirstName
    ];
  }

  @IsTest
  static void scoringRules() {
    RetentionService.Risk none = RetentionService.score(95, 80, 0, null, 90);
    Assert.areEqual(0, none.score, 'No risk');
    Assert.areEqual('Low', none.level, 'Low');
    RetentionService.Risk medium = RetentionService.score(70, 80, 1, null, 60);
    Assert.areEqual(40, medium.score, 'Attendance 30 + score 10');
    Assert.areEqual('Medium', medium.level, 'Medium');
    RetentionService.Risk high = RetentionService.score(40, 80, 3, 45, 30);
    Assert.areEqual(100, high.score, 'Capped at 100');
    Assert.areEqual('High', high.level, 'High');
    Assert.areEqual(4, high.reasons.size(), 'Every reason listed');
  }

  @IsTest
  static void nightlyJobFlagsHighRiskAndCreatesATask() {
    List<CourseOfferingParticipant> rows = enrolments();
    Database.update(
      new CourseOfferingParticipant(
        Id = rows[0].Id,
        Attendance_Rate__c = 40,
        Course_Score__c = 45
      ),
      AccessLevel.SYSTEM_MODE
    );
    Test.startTest();
    Id jobId = RetentionJob.run();
    Test.stopTest();
    Assert.isNotNull(jobId, 'Started');
    CourseOfferingParticipant risky = [
      SELECT Risk_Score__c, Risk_Level__c, Risk_Reasons__c, Retention_Status__c
      FROM CourseOfferingParticipant
      WHERE Id = :rows[0].Id
    ];
    Assert.areEqual(60, risky.Risk_Score__c, 'Attendance 40 + score 20');
    Assert.areEqual('High', risky.Risk_Level__c, 'High');
    Assert.areEqual('Follow-up Needed', risky.Retention_Status__c, 'Follow-up');
    Assert.isTrue(
      risky.Risk_Reasons__c.contains('Attendance 40%'),
      risky.Risk_Reasons__c
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Task
        WHERE
          WhatId = :rows[0].ParticipantAccountId
          AND Subject LIKE 'Retention follow-up%'
      ],
      'Task created'
    );
    Assert.areEqual(
      'Low',
      [
        SELECT Risk_Level__c
        FROM CourseOfferingParticipant
        WHERE Id = :rows[1].Id
      ]
      .Risk_Level__c,
      'Other learner is fine'
    );
    // Assessing again does not create a second task.
    RetentionService.assess(new Set<Id>{ rows[0].Id });
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Task WHERE WhatId = :rows[0].ParticipantAccountId],
      'No duplicate task'
    );
  }

  @IsTest
  static void absencesInARowAndOverdueFees() {
    List<CourseOfferingParticipant> rows = enrolments();
    CourseOfferingParticipant e = rows[0];
    List<Class_Session__c> sessions = new List<Class_Session__c>();
    for (Integer i = 1; i <= 3; i++) {
      Datetime start = System.now().addDays(-i);
      sessions.add(
        new Class_Session__c(
          Course_Offering__c = e.CourseOfferingId,
          Start__c = start,
          End__c = start.addHours(1)
        )
      );
    }
    insert sessions;
    List<Session_Attendance__c> marks = new List<Session_Attendance__c>();
    for (Class_Session__c s : sessions) {
      marks.add(
        new Session_Attendance__c(
          Class_Session__c = s.Id,
          Enrolment__c = e.Id,
          Learner__c = e.ParticipantContactId,
          Status__c = 'Absent'
        )
      );
    }
    Database.insert(marks, AccessLevel.SYSTEM_MODE);
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      Id invoiceId = BillingService.createInvoice(e.Id, true);
      Database.update(
        new Student_Invoice__c(
          Id = invoiceId,
          Due_Date__c = Date.today().addDays(-40)
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
    Test.startTest();
    RetentionService.assess(new Set<Id>{ e.Id });
    Test.stopTest();
    CourseOfferingParticipant result = [
      SELECT Risk_Score__c, Risk_Level__c, Risk_Reasons__c
      FROM CourseOfferingParticipant
      WHERE Id = :e.Id
    ];
    Assert.areEqual(
      50,
      result.Risk_Score__c,
      'Absences 25 + overdue 25: ' + result.Risk_Reasons__c
    );
    Assert.areEqual('High', result.Risk_Level__c, 'High');
    Assert.isTrue(
      result.Risk_Reasons__c.contains('Absent 3 sessions in a row'),
      result.Risk_Reasons__c
    );
    Assert.isTrue(
      result.Risk_Reasons__c.contains('Fees overdue 40 days'),
      result.Risk_Reasons__c
    );
  }

  @IsTest
  static void deskFollowUpAndReenrolmentInvites() {
    List<CourseOfferingParticipant> rows = enrolments();
    Database.update(
      new CourseOfferingParticipant(Id = rows[0].Id, Attendance_Rate__c = 50),
      AccessLevel.SYSTEM_MODE
    );
    RetentionService.assess(new Set<Id>{ rows[0].Id, rows[1].Id });
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      RetentionService.Desk desk = RetentionController.getDesk(null, 'All');
      Assert.areEqual(1, desk.atRisk.size(), 'One at risk');
      Assert.areEqual(
        'Medium',
        desk.atRisk[0].level,
        'Attendance 50% alone is Medium'
      );
      Assert.isTrue(desk.canRecalculate, 'Admins can recalculate');
      Assert.areEqual(
        2,
        desk.candidates.size(),
        'Both learners finish in 20 days'
      );

      try {
        RetentionController.recordFollowUp(rows[0].Id, 'Contacted', '');
        Assert.fail('A note is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('note'), e.getMessage());
      }
      RetentionController.recordFollowUp(
        rows[0].Id,
        'Contacted',
        'Called the mother; travel issue'
      );
      CourseOfferingParticipant updated = [
        SELECT Retention_Status__c, Retention_Note__c
        FROM CourseOfferingParticipant
        WHERE Id = :rows[0].Id
      ];
      Assert.areEqual('Contacted', updated.Retention_Status__c, 'Status');
      Assert.isTrue(
        updated.Retention_Note__c.startsWith('Called the mother'),
        updated.Retention_Note__c
      );

      MessageService.disabled = false;
      Integer created = RetentionController.invite(
        new List<Id>{ rows[0].Id, rows[1].Id }
      );
      Assert.isTrue(created >= 2, 'Invites sent: ' + created);
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM CourseOfferingParticipant
          WHERE
            Reenrolment_Invited_On__c != NULL
            AND Branch__r.Branch_Code__c = 'RET-01'
        ],
        'Invites recorded'
      );
      Assert.isNotNull(
        RetentionController.recalculate(),
        'Recalculation started'
      );
      Test.stopTest();
    }
    Assert.isTrue(
      [SELECT COUNT() FROM Message__c WHERE Event__c = 'Re_Enrolment_Invite'] >=
      2,
      'Messages created'
    );
  }

  @IsTest
  static void validation() {
    List<CourseOfferingParticipant> rows = enrolments();
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(TestDataFactory.admin()) {
      try {
        RetentionController.recordFollowUp(rows[0].Id, 'Bogus', 'x');
        Assert.fail('Unknown outcome');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Choose'), e.getMessage());
      }
      try {
        RetentionController.invite(new List<Id>());
        Assert.fail('Nothing selected');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Choose'), e.getMessage());
      }
    }
    System.runAs(teacher) {
      try {
        RetentionService.recordFollowUp(rows[0].Id, 'Retained', null);
        Assert.fail('Teachers cannot update enrolments');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('cannot update'), e.getMessage());
      }
      try {
        RetentionController.recalculate();
        Assert.fail('Administrators only');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('administrators'),
          e.getMessage()
        );
      }
    }
  }
}
