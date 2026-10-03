@IsTest
private class PortalServiceTest {
  private class Family {
    Id guardianContactId;
    Id learnerContactId;
    Id hiddenSiblingContactId;
    Id strangerContactId;
    Id invoiceId;
  }

  /**
   * Guardian with two linked learners: one with portal access (enrolled,
   * invoiced, with a session, attendance and a published result) and one
   * without; plus an unrelated learner.
   */
  private static Family family() {
    TestDataFactory.createReferenceData();
    DocumentService.suppressJobs = true;
    Family fam = new Family();
    Branch__c branch = TestDataFactory.createBranch();
    LearningCourse course = TestDataFactory.createCourse('Geometry');
    insert new Fee_Price__c(
      Learning_Course__c = course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = 1000,
      Effective_From__c = Date.today().addDays(-1)
    );
    List<Account> people = new List<Account>{
      PersonAccountService.buildPerson(
        'Gita',
        'Guardian' + Crypto.getRandomInteger(),
        'gita@example.com',
        null,
        branch.Id,
        'Guardian'
      ),
      PersonAccountService.buildPerson(
        'Lila',
        'Learner' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      ),
      PersonAccountService.buildPerson(
        'Hari',
        'Hidden' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      ),
      PersonAccountService.buildPerson(
        'Sam',
        'Stranger' + Crypto.getRandomInteger(),
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
    fam.guardianContactId = byId.get(people[0].Id).PersonContactId;
    fam.learnerContactId = byId.get(people[1].Id).PersonContactId;
    fam.hiddenSiblingContactId = byId.get(people[2].Id).PersonContactId;
    fam.strangerContactId = byId.get(people[3].Id).PersonContactId;

    GuardianRelationshipService.GuardianLink visible = new GuardianRelationshipService.GuardianLink();
    visible.guardianContactId = fam.guardianContactId;
    visible.learnerContactId = fam.learnerContactId;
    visible.relationship = 'Mother';
    GuardianRelationshipService.GuardianLink hidden = new GuardianRelationshipService.GuardianLink();
    hidden.guardianContactId = fam.guardianContactId;
    hidden.learnerContactId = fam.hiddenSiblingContactId;
    hidden.relationship = 'Mother';
    hidden.portalAccess = false;
    GuardianRelationshipService.link(
      new List<GuardianRelationshipService.GuardianLink>{ visible, hidden }
    );

    CourseOffering offering = TestDataFactory.createOffering(
      course.Id,
      branch.Id,
      10
    );
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = people[1].Id;
    request.offeringId = offering.Id;
    Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
    fam.invoiceId = BillingService.createInvoice(enrolmentId, true);

    Datetime tomorrow = Datetime.now().addDays(1);
    Class_Session__c past = new Class_Session__c(
      Course_Offering__c = offering.Id,
      Start__c = Datetime.now().addDays(-2),
      End__c = Datetime.now().addDays(-2).addHours(1)
    );
    Class_Session__c upcoming = new Class_Session__c(
      Course_Offering__c = offering.Id,
      Start__c = tomorrow,
      End__c = tomorrow.addHours(1),
      Meeting_Url__c = 'https://meet.example.com/geo'
    );
    insert new List<Class_Session__c>{ past, upcoming };
    Database.insert(
      new Session_Attendance__c(
        Class_Session__c = past.Id,
        Learner__c = fam.learnerContactId,
        Enrolment__c = enrolmentId,
        Status__c = 'Late',
        Minutes_Late__c = 5
      ),
      AccessLevel.SYSTEM_MODE
    );
    Course_Assessment__c assessment = new Course_Assessment__c(
      Name = 'Angles quiz',
      Course_Offering__c = offering.Id,
      Max_Score__c = 20,
      Assessment_Type__c = 'Quiz'
    );
    insert assessment;
    AssessmentService.ResultRow row = new AssessmentService.ResultRow();
    row.learnerContactId = fam.learnerContactId;
    row.enrolmentId = enrolmentId;
    row.learnerName = 'Lila';
    row.score = 18;
    AssessmentService.saveResults(
      assessment.Id,
      new List<AssessmentService.ResultRow>{ row }
    );
    AssessmentService.publish(assessment.Id);
    return fam;
  }

  @IsTest
  static void guardianSeesOnlyAuthorisedLearners() {
    User admin = TestDataFactory.admin();
    TestDataFactory.giveRole(admin.Id);
    Family fam;
    System.runAs(admin) {
      fam = family();
    }
    User guardian = TestDataFactory.createPortalUser(fam.guardianContactId);

    System.runAs(guardian) {
      PortalService.Home home = PortalController.getHome();
      Assert.isTrue(home.isGuardian, 'Guardian');
      Assert.isTrue(home.viewerName.startsWith('Gita'), home.viewerName);
      Assert.areEqual(
        1,
        home.learners.size(),
        'Only the learner with portal access'
      );
      PortalService.LearnerCard card = home.learners[0];
      Assert.areEqual(
        fam.learnerContactId,
        card.learnerContactId,
        'Linked learner'
      );
      Assert.isFalse(card.isSelf, 'Not the viewer');
      Assert.areEqual(1, card.activeClasses, 'One class');
      Assert.areEqual(
        1180,
        card.balanceDue,
        'Invoice balance (1000 + 18% tax)'
      );
      Assert.areEqual(1180, home.totalDue, 'Family total');
      Assert.isNotNull(card.nextSessionStart, 'Next session');

      PortalService.LearnerDetail detail = PortalController.getLearner(
        fam.learnerContactId
      );
      Assert.areEqual(1, detail.classes.size(), 'Classes');
      Assert.areEqual(1, detail.upcoming.size(), 'Upcoming session only');
      Assert.areEqual(
        'https://meet.example.com/geo',
        detail.upcoming[0].meetingUrl,
        'Join link'
      );
      Assert.areEqual(1, detail.attendance.size(), 'Attendance');
      Assert.areEqual('Late', detail.attendance[0].status, 'Late mark');
      Assert.areEqual(1, detail.results.size(), 'Published result');
      Assert.areEqual('A+', detail.results[0].grade, '18/20 = 90%');
      Assert.areEqual(1, detail.invoices.size(), 'Invoice');
      Assert.areEqual(fam.invoiceId, detail.invoices[0].id, 'Same invoice');

      for (
        Id forbidden : new List<Id>{
          fam.hiddenSiblingContactId,
          fam.strangerContactId
        }
      ) {
        try {
          PortalController.getLearner(forbidden);
          Assert.fail('Must not see ' + forbidden);
        } catch (AuraHandledException e) {
          Assert.isTrue(
            e.getMessage().contains('do not have access'),
            e.getMessage()
          );
        }
      }
    }
  }

  @IsTest
  static void learnerSeesThemselves() {
    Family fam;
    System.runAs(TestDataFactory.admin()) {
      fam = family();
      PortalService.viewerOverride = fam.learnerContactId;
      PortalService.Home home = PortalService.home();
      Assert.isFalse(home.isGuardian, 'Not a guardian');
      Assert.areEqual(1, home.learners.size(), 'Self');
      Assert.isTrue(home.learners[0].isSelf, 'Viewer is the learner');
      Assert.areEqual(
        1,
        PortalService.learner(fam.learnerContactId).results.size(),
        'Own results'
      );

      PortalService.viewerOverride = fam.strangerContactId;
      Assert.isFalse(
        PortalService.authorisedLearners(fam.strangerContactId)
          .contains(fam.learnerContactId),
        'Strangers are not authorised'
      );
    }
  }

  @IsTest
  static void internalUsersAreTurnedAway() {
    System.runAs(TestDataFactory.admin()) {
      try {
        PortalController.getHome();
        Assert.fail('Internal users have no portal contact');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('signed in to the portal'),
          e.getMessage()
        );
      }
    }
  }
}
