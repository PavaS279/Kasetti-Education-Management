@IsTest
private class ApplicationServiceTest {
  private static IndividualApplication createApplication(
    Id branchId,
    Date birthdate,
    LearningCourse course
  ) {
    Account learner = PersonAccountService.buildPerson(
      'Ria',
      'Applicant' + Crypto.getRandomInteger(),
      null,
      null,
      branchId,
      'Learner'
    );
    learner.PersonBirthdate = birthdate;
    insert learner;
    learner = [SELECT Id, PersonContactId FROM Account WHERE Id = :learner.Id];
    IndividualApplication application = new IndividualApplication(
      Category = 'Education',
      AccountId = learner.Id,
      ContactId = learner.PersonContactId,
      Status = 'Processing',
      Branch__c = branchId,
      Learning_Course__c = course == null ? null : course.Id
    );
    insert application;
    return application;
  }

  private static LearningCourse course(Integer minAge, Integer maxAge) {
    LearningCourse c = TestDataFactory.createCourse(
      'Course ' + Crypto.getRandomInteger()
    );
    update new LearningCourse(
      Id = c.Id,
      Minimum_Age__c = minAge,
      Maximum_Age__c = maxAge
    );
    return c;
  }

  private static void completeChecklist(Id applicationId) {
    for (DocumentChecklistItem item : [
      SELECT Id, IsRequired
      FROM DocumentChecklistItem
      WHERE
        ParentRecordId = :applicationId
        AND Status NOT IN ('Accepted', 'Waived')
    ]) {
      ApplicationController.updateChecklistItem(
        item.Id,
        item.IsRequired ? 'Accepted' : 'Waived',
        null
      );
    }
  }

  @IsTest
  static void createsChecklistAndTracksCompletion() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      IndividualApplication application = createApplication(
        branch.Id,
        null,
        null
      );
      List<DocumentChecklistItem> items = [
        SELECT Id, IsRequired, Status
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :application.Id
      ];
      Integer required = 0;
      for (
        Application_Checklist_Item__mdt t : Application_Checklist_Item__mdt.getAll()
          .values()
      ) {
        if (t.Active__c && t.Required__c) {
          required++;
        }
      }
      Assert.areEqual(
        Application_Checklist_Item__mdt.getAll().size(),
        items.size(),
        'One item per template row'
      );
      Assert.isFalse(
        [
          SELECT Checklist_Complete__c
          FROM IndividualApplication
          WHERE Id = :application.Id
        ]
        .Checklist_Complete__c,
        'Starts incomplete'
      );

      try {
        ApplicationController.updateChecklistItem(
          items[0].Id,
          'Rejected',
          null
        );
        Assert.fail('Rejecting without reason must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      ApplicationController.updateChecklistItem(
        items[0].Id,
        'Rejected',
        'Blurred scan'
      );
      completeChecklist(application.Id);
      ApplicationController.ApplicationView view = ApplicationController.getApplication(
        application.Id
      );
      Assert.isTrue(
        view.application.Checklist_Complete__c,
        'Complete when required items are accepted'
      );
      Assert.areEqual(0, view.requiredOpen, 'No open required items');

      Id extra = ApplicationController.addChecklistItem(
        application.Id,
        'Medical form',
        true,
        'Signed by a doctor'
      );
      Assert.isFalse(
        [
          SELECT Checklist_Complete__c
          FROM IndividualApplication
          WHERE Id = :application.Id
        ]
        .Checklist_Complete__c,
        'New required item reopens checklist'
      );
      delete new DocumentChecklistItem(Id = extra);
      Assert.isTrue(
        [
          SELECT Checklist_Complete__c
          FROM IndividualApplication
          WHERE Id = :application.Id
        ]
        .Checklist_Complete__c,
        'Deleting it completes the checklist again'
      );
      Assert.isTrue(required > 0, 'Template has required items');
    }
  }

  @IsTest
  static void evaluatesAgeEligibility() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse juniors = course(8, 12);
      IndividualApplication eligible = createApplication(
        branch.Id,
        Date.today().addYears(-10),
        juniors
      );
      IndividualApplication tooOld = createApplication(
        branch.Id,
        Date.today().addYears(-15),
        juniors
      );
      IndividualApplication noBirthdate = createApplication(
        branch.Id,
        null,
        juniors
      );
      IndividualApplication noLimits = createApplication(
        branch.Id,
        null,
        course(null, null)
      );
      Map<Id, IndividualApplication> saved = new Map<Id, IndividualApplication>(
        [
          SELECT Eligibility_Status__c
          FROM IndividualApplication
          WHERE
            Id IN :new List<Id>{
              eligible.Id,
              tooOld.Id,
              noBirthdate.Id,
              noLimits.Id
            }
        ]
      );
      Assert.areEqual(
        'Eligible',
        saved.get(eligible.Id).Eligibility_Status__c,
        'In range'
      );
      Assert.areEqual(
        'Not Eligible',
        saved.get(tooOld.Id).Eligibility_Status__c,
        'Too old'
      );
      Assert.areEqual(
        'Not Checked',
        saved.get(noBirthdate.Id).Eligibility_Status__c,
        'Missing birthdate'
      );
      Assert.areEqual(
        'Eligible',
        saved.get(noLimits.Id).Eligibility_Status__c,
        'No limits'
      );

      LearningCourse seniors = course(14, null);
      update new IndividualApplication(
        Id = tooOld.Id,
        Learning_Course__c = seniors.Id
      );
      Assert.areEqual(
        'Eligible',
        [
          SELECT Eligibility_Status__c
          FROM IndividualApplication
          WHERE Id = :tooOld.Id
        ]
        .Eligibility_Status__c,
        'Re-evaluated on course change'
      );
      Assert.areEqual(
        9,
        ApplicationService.ageOn(
          Date.newInstance(2016, 12, 31),
          Date.newInstance(2026, 12, 30)
        ),
        'Birthday not yet reached'
      );
    }
  }

  @IsTest
  static void runsReviewDecisionAndOfferLifecycle() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      IndividualApplication application = createApplication(
        branch.Id,
        Date.today().addYears(-15),
        course(8, 12)
      );

      try {
        ApplicationController.performAction(application.Id, 'ready', null);
        Assert.fail('Cannot skip review');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('In Review'), e.getMessage());
      }
      ApplicationController.performAction(application.Id, 'submit', null);
      try {
        ApplicationController.performAction(application.Id, 'ready', null);
        Assert.fail('Checklist must be complete');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('checklist'), e.getMessage());
      }
      completeChecklist(application.Id);
      try {
        ApplicationController.performAction(application.Id, 'ready', null);
        Assert.fail('Ineligible applicant needs an override');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('not eligible'), e.getMessage());
      }
      try {
        ApplicationController.performAction(
          application.Id,
          'override',
          'Exceptional maturity'
        );
        Assert.fail('Override requires the custom permission');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
  }

  @IsTest
  static void overrideThenAdmitAndAcceptOffer() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    User admin = TestDataFactory.admin();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      TestDataFactory.assignPermissionSets(
        admin.Id,
        new List<String>{ 'KEM_Eligibility_Override' }
      );
    }
    System.runAs(admin) {
      Branch__c branch = TestDataFactory.createBranch();
      IndividualApplication application = createApplication(
        branch.Id,
        Date.today().addYears(-15),
        course(8, 12)
      );
      ApplicationController.performAction(application.Id, 'submit', null);
      completeChecklist(application.Id);
      ApplicationController.performAction(
        application.Id,
        'override',
        'Exceptional maturity'
      );
      ApplicationController.performAction(application.Id, 'ready', null);
      try {
        ApplicationController.decide(application.Id, 'Reject', null, null);
        Assert.fail('Reject needs a reason');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      ApplicationController.decide(application.Id, 'Admit', null, 7);
      IndividualApplication decided = [
        SELECT
          Status,
          Decision__c,
          Offer_Status__c,
          Offer_Expiry_Date__c,
          Decided_By__c,
          Eligibility_Status__c
        FROM IndividualApplication
        WHERE Id = :application.Id
      ];
      Assert.areEqual(
        'Application Decision',
        decided.Status,
        'Decision recorded'
      );
      Assert.areEqual(
        'Overridden',
        decided.Eligibility_Status__c,
        'Override kept'
      );
      Assert.areEqual('Offered', decided.Offer_Status__c, 'Offer made');
      Assert.areEqual(
        Date.today().addDays(7),
        decided.Offer_Expiry_Date__c,
        'Expiry from validity days'
      );
      Assert.areEqual(admin.Id, decided.Decided_By__c, 'Decider stamped');

      ApplicationController.performAction(application.Id, 'accept', null);
      Assert.areEqual(
        'Accepted',
        [
          SELECT Offer_Status__c
          FROM IndividualApplication
          WHERE Id = :application.Id
        ]
        .Offer_Status__c,
        'Offer accepted'
      );
      try {
        ApplicationController.performAction(application.Id, 'accept', null);
        Assert.fail('No open offer');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('no open offer'), e.getMessage());
      }
    }
  }

  @IsTest
  static void expiresOffersAndBlocksLateAcceptance() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      IndividualApplication application = createApplication(
        branch.Id,
        null,
        null
      );
      ApplicationService.submitForReview(application.Id);
      completeChecklist(application.Id);
      ApplicationService.markReadyForDecision(application.Id);
      ApplicationService.decide(application.Id, 'Admit', null, null);
      // Backdate the (system-managed) expiry to simulate an offer that lapsed.
      Database.update(
        new IndividualApplication(
          Id = application.Id,
          Offer_Expiry_Date__c = Date.today().addDays(-1)
        ),
        AccessLevel.SYSTEM_MODE
      );
      try {
        ApplicationService.respondToOffer(application.Id, true);
        Assert.fail('Expired offer cannot be accepted');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('expired'), e.getMessage());
      }
      Test.startTest();
      new OfferExpiryJob().execute((SchedulableContext) null);
      Test.stopTest();
      Assert.areEqual(
        'Expired',
        [
          SELECT Offer_Status__c
          FROM IndividualApplication
          WHERE Id = :application.Id
        ]
        .Offer_Status__c,
        'Batch expired the offer'
      );
    }
  }

  @IsTest
  static void waitlistRejectWithdrawAndQueue() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      IndividualApplication waitlisted = createApplication(
        branch.Id,
        null,
        null
      );
      ApplicationService.submitForReview(waitlisted.Id);
      completeChecklist(waitlisted.Id);
      ApplicationService.markReadyForDecision(waitlisted.Id);
      ApplicationController.decide(
        waitlisted.Id,
        'Waitlist',
        'Class full',
        null
      );
      Assert.areEqual(
        'Not Offered',
        [
          SELECT Offer_Status__c
          FROM IndividualApplication
          WHERE Id = :waitlisted.Id
        ]
        .Offer_Status__c,
        'No offer when waitlisted'
      );

      IndividualApplication returned = createApplication(branch.Id, null, null);
      ApplicationService.submitForReview(returned.Id);
      ApplicationController.performAction(returned.Id, 'return', null);
      Assert.areEqual(
        'Processing',
        [SELECT Status FROM IndividualApplication WHERE Id = :returned.Id]
        .Status,
        'Returned to applicant'
      );

      try {
        ApplicationController.performAction(returned.Id, 'withdraw', null);
        Assert.fail('Withdraw needs a reason');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      ApplicationController.performAction(
        returned.Id,
        'withdraw',
        'Family relocated'
      );
      try {
        ApplicationService.withdraw(returned.Id, 'Again');
        Assert.fail('Already closed');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('closed'), e.getMessage());
      }

      Database.SaveResult skip = Database.update(
        new IndividualApplication(Id = returned.Id, Status = 'Enrolled'),
        false
      );
      Assert.isFalse(
        skip.isSuccess(),
        'Withdrawn to Enrolled is not an allowed transition'
      );

      IndividualApplication fresh = createApplication(branch.Id, null, null);
      List<ApplicationController.QueueColumn> queue = ApplicationController.getQueue(
        branch.Id
      );
      Assert.areEqual(4, queue.size(), 'Four queue stages');
      Assert.areEqual(
        1,
        queue[0].applications.size(),
        'Fresh application in Processing'
      );
      Assert.areEqual(
        fresh.Id,
        queue[0].applications[0].Id,
        'Correct application queued'
      );
      try {
        ApplicationController.performAction(fresh.Id, 'teleport', null);
        Assert.fail('Unknown action');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Unknown action'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void counsellorRunsReviewButTeacherCannot() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      User counsellor = TestDataFactory.createCounsellor(branch.Id);
      User teacher = TestDataFactory.createUserWithLicense(
        TestDataFactory.persona('KEM_Teacher')
      );
      IndividualApplication application;
      System.runAs(counsellor) {
        Account learner = PersonAccountService.buildPerson(
          'Tara',
          'Persona',
          null,
          null,
          branch.Id,
          'Learner'
        );
        Database.insert(learner, AccessLevel.USER_MODE);
        learner = [
          SELECT Id, PersonContactId
          FROM Account
          WHERE Id = :learner.Id
        ];
        application = new IndividualApplication(
          Category = 'Education',
          AccountId = learner.Id,
          ContactId = learner.PersonContactId,
          Status = 'Processing',
          Branch__c = branch.Id
        );
        Database.insert(application, AccessLevel.USER_MODE);
        ApplicationController.performAction(application.Id, 'submit', null);
        completeChecklist(application.Id);
        ApplicationController.performAction(application.Id, 'ready', null);
        ApplicationController.decide(application.Id, 'Admit', null, null);
        Assert.areEqual(
          'Offered',
          ApplicationController.getApplication(application.Id)
            .application.Offer_Status__c,
          'Counsellor completes the admission decision'
        );
      }
      System.runAs(teacher) {
        try {
          ApplicationController.decide(application.Id, 'Reject', 'x', null);
          Assert.fail('Teacher must not decide applications');
        } catch (AuraHandledException e) {
          Assert.isNotNull(e.getMessage(), 'Access denied for teacher');
        }
      }
    }
  }
}
