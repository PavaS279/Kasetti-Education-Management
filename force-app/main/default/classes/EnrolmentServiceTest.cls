@IsTest
private class EnrolmentServiceTest {
  private class Fixture {
    Branch__c branch;
    LearningCourse course;
    CourseOffering offering;
    List<Account> learners = new List<Account>();
  }

  private static Fixture fixture(Integer capacity) {
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    f.course = TestDataFactory.createCourse('Algebra');
    insert new List<Fee_Price__c>{
      new Fee_Price__c(
        Learning_Course__c = f.course.Id,
        Fee_Type__c = 'Admission',
        Billing_Frequency__c = 'One-time',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-10)
      ),
      new Fee_Price__c(
        Learning_Course__c = f.course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 5000,
        Effective_From__c = Date.today().addDays(-10)
      )
    };
    f.offering = TestDataFactory.createOffering(
      f.course.Id,
      f.branch.Id,
      capacity
    );
    for (Integer i = 0; i < 3; i++) {
      f.learners.add(
        PersonAccountService.buildPerson(
          'L' + i,
          'Enrol' + i + Crypto.getRandomInteger(),
          null,
          null,
          f.branch.Id,
          'Learner'
        )
      );
    }
    insert f.learners;
    return f;
  }

  private static EnrolmentService.EnrolmentRequest request(
    Id learnerId,
    Id offeringId,
    String code
  ) {
    EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
    r.learnerAccountId = learnerId;
    r.offeringId = offeringId;
    r.discountCode = code;
    return r;
  }

  @IsTest
  static void enrolsWithPriceSnapshotAndSeatControl() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(2);
      EnrolmentService.EnrolmentResult first = EnrolmentController.enrol(
        request(f.learners[0].Id, f.offering.Id, null)
      );
      CourseOfferingParticipant enrolment = [
        SELECT
          ParticipationStatus,
          Agreed_Subtotal__c,
          Agreed_Tax__c,
          Agreed_Total__c,
          Branch__c,
          Discount_Approval_Status__c,
          Billing_Status__c
        FROM CourseOfferingParticipant
        WHERE Id = :first.enrolmentId
      ];
      Assert.areEqual('Enrolled', enrolment.ParticipationStatus, 'Enrolled');
      Assert.areEqual(
        6000,
        enrolment.Agreed_Subtotal__c,
        'Admission + tuition'
      );
      Assert.areEqual(1080, enrolment.Agreed_Tax__c, '18% branch tax');
      Assert.areEqual(7080, enrolment.Agreed_Total__c, 'Agreed total');
      Assert.areEqual(f.branch.Id, enrolment.Branch__c, 'Branch stamped');
      Assert.areEqual(
        'Not Required',
        enrolment.Discount_Approval_Status__c,
        'No discount'
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Enrolment_Fee_Line__c
          WHERE Enrolment__c = :first.enrolmentId
        ],
        'Two fee lines snapshotted'
      );
      Assert.areEqual(1, first.seatsRemaining, 'One seat left');

      EnrolmentController.enrol(request(f.learners[1].Id, f.offering.Id, null));
      CourseOffering full = [
        SELECT Seats_Taken__c, Seats_Available__c, Class_Status__c
        FROM CourseOffering
        WHERE Id = :f.offering.Id
      ];
      Assert.areEqual(2, full.Seats_Taken__c, 'Seats counted');
      Assert.areEqual(0, full.Seats_Available__c, 'No seats available');
      Assert.areEqual('Full', full.Class_Status__c, 'Class becomes full');

      EnrolmentService.Preview preview = EnrolmentController.previewEnrolment(
        request(f.learners[2].Id, f.offering.Id, null)
      );
      Assert.isFalse(preview.blockers.isEmpty(), 'Preview reports a blocker');
      try {
        EnrolmentController.enrol(
          request(f.learners[2].Id, f.offering.Id, null)
        );
        Assert.fail('Full class must reject enrolment');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('full'), e.getMessage());
      }
    }
  }

  @IsTest
  static void snapshotIsNotAffectedByLaterPriceChanges() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(5);
      Id enrolmentId = EnrolmentService.enrol(
          request(f.learners[0].Id, f.offering.Id, null)
        )
        .enrolmentId;
      Fee_Price__c tuition = [
        SELECT Id
        FROM Fee_Price__c
        WHERE Learning_Course__c = :f.course.Id AND Fee_Type__c = 'Tuition'
      ];
      update new Fee_Price__c(Id = tuition.Id, Effective_To__c = Date.today());
      insert new Fee_Price__c(
        Learning_Course__c = f.course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 9999,
        Effective_From__c = Date.today().addDays(1)
      );
      Assert.areEqual(
        5000,
        [
          SELECT Unit_Amount__c
          FROM Enrolment_Fee_Line__c
          WHERE Enrolment__c = :enrolmentId AND Fee_Type__c = 'Tuition'
        ]
        .Unit_Amount__c,
        'Agreed tuition unchanged'
      );
      Assert.areEqual(
        7080,
        [
          SELECT Agreed_Total__c
          FROM CourseOfferingParticipant
          WHERE Id = :enrolmentId
        ]
        .Agreed_Total__c,
        'Agreed total unchanged'
      );
    }
  }

  @IsTest
  static void blocksInvalidEnrolments() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(5);
      EnrolmentService.enrol(request(f.learners[0].Id, f.offering.Id, null));
      Map<String, EnrolmentService.EnrolmentRequest> cases = new Map<String, EnrolmentService.EnrolmentRequest>{
        'already enrolled' => request(f.learners[0].Id, f.offering.Id, null),
        'does not exist' => request(f.learners[1].Id, f.offering.Id, 'NOCODE')
      };
      Account guardian = PersonAccountService.buildPerson(
        'G',
        'NotLearner',
        null,
        null,
        f.branch.Id,
        'Guardian'
      );
      insert guardian;
      cases.put('Only learners', request(guardian.Id, f.offering.Id, null));
      CourseOffering planned = TestDataFactory.createOffering(
        f.course.Id,
        f.branch.Id,
        5
      );
      update new CourseOffering(Id = planned.Id, Class_Status__c = 'Planned');
      cases.put(
        'not taking enrolments',
        request(f.learners[1].Id, planned.Id, null)
      );
      LearningCourse unpriced = TestDataFactory.createCourse('Unpriced');
      cases.put(
        'No price',
        request(
          f.learners[1].Id,
          TestDataFactory.createOffering(unpriced.Id, f.branch.Id, 5).Id,
          null
        )
      );
      cases.put('Choose a learner', new EnrolmentService.EnrolmentRequest());
      for (String expected : cases.keySet()) {
        try {
          EnrolmentService.enrol(cases.get(expected));
          Assert.fail('Expected failure: ' + expected);
        } catch (AppException e) {
          Assert.isTrue(
            e.getMessage().contains(expected),
            expected + ' → ' + e.getMessage()
          );
        }
      }
    }
  }

  @IsTest
  static void enrolsFromAcceptedApplication() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(5);
      Account learner = [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id = :f.learners[0].Id
      ];
      IndividualApplication application = new IndividualApplication(
        Category = 'Education',
        AccountId = learner.Id,
        ContactId = learner.PersonContactId,
        Status = 'Processing'
      );
      insert application;
      EnrolmentService.EnrolmentRequest r = request(
        learner.Id,
        f.offering.Id,
        null
      );
      r.applicationId = application.Id;
      try {
        EnrolmentService.enrol(r);
        Assert.fail('Offer must be accepted first');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('accept the offer'),
          e.getMessage()
        );
      }
      ApplicationService.submitForReview(application.Id);
      for (DocumentChecklistItem item : [
        SELECT Id, IsRequired
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :application.Id
      ]) {
        ApplicationService.updateChecklistItem(item.Id, 'Accepted', null);
      }
      ApplicationService.markReadyForDecision(application.Id);
      ApplicationService.decide(application.Id, 'Admit', null, null);
      ApplicationService.respondToOffer(application.Id, true);

      EnrolmentService.EnrolmentRequest other = request(
        f.learners[1].Id,
        f.offering.Id,
        null
      );
      other.applicationId = application.Id;
      try {
        EnrolmentService.enrol(other);
        Assert.fail('Application belongs to someone else');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('does not belong'),
          e.getMessage()
        );
      }

      Id enrolmentId = EnrolmentService.enrol(r).enrolmentId;
      Assert.areEqual(
        'Enrolled',
        [SELECT Status FROM IndividualApplication WHERE Id = :application.Id]
        .Status,
        'Application marked enrolled'
      );
      Assert.areEqual(
        application.Id,
        [
          SELECT Application__c
          FROM CourseOfferingParticipant
          WHERE Id = :enrolmentId
        ]
        .Application__c,
        'Enrolment linked to application'
      );
    }
  }

  @IsTest
  static void approvesAndRejectsDiscounts() {
    User admin = TestDataFactory.admin();
    User finance = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Finance')
    );
    System.runAs(admin) {
      Fixture f = fixture(5);
      insert new Discount__c(
        Name = 'Staff',
        Code__c = 'STAFF50',
        Discount_Type__c = 'Percentage',
        Value__c = 50,
        Fee_Type__c = 'Tuition',
        Active__c = true,
        Requires_Approval__c = true
      );
      Id approvedId = EnrolmentService.enrol(
          request(f.learners[0].Id, f.offering.Id, 'staff50')
        )
        .enrolmentId;
      Id rejectedId = EnrolmentService.enrol(
          request(f.learners[1].Id, f.offering.Id, 'STAFF50')
        )
        .enrolmentId;
      Assert.areEqual(
        'Pending',
        [
          SELECT Discount_Approval_Status__c
          FROM CourseOfferingParticipant
          WHERE Id = :approvedId
        ]
        .Discount_Approval_Status__c,
        'Approval pending'
      );
      Assert.areEqual(
        2,
        [SELECT Times_Used__c FROM Discount__c WHERE Code__c = 'STAFF50']
        .Times_Used__c,
        'Usage counted'
      );
      User counsellor = TestDataFactory.createCounsellor(f.branch.Id);
      System.runAs(counsellor) {
        try {
          EnrolmentService.decideDiscount(approvedId, true);
          Assert.fail('Counsellors cannot approve discounts');
        } catch (AppException e) {
          Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
        }
      }
    }
    System.runAs(finance) {
      EnrolmentController.decideDiscount(
        [
          SELECT Id
          FROM CourseOfferingParticipant
          WHERE Discount_Approval_Status__c = 'Pending'
          ORDER BY CreatedDate
          LIMIT 1
        ]
        .Id,
        true
      );
    }
    System.runAs(finance) {
      Id rejectedId = [
        SELECT Id
        FROM CourseOfferingParticipant
        WHERE Discount_Approval_Status__c = 'Pending'
        LIMIT 1
      ]
      .Id;
      EnrolmentController.decideDiscount(rejectedId, false);
      CourseOfferingParticipant repriced = [
        SELECT Discount_Approval_Status__c, Agreed_Discount__c, Agreed_Total__c
        FROM CourseOfferingParticipant
        WHERE Id = :rejectedId
      ];
      Assert.areEqual(
        'Rejected',
        repriced.Discount_Approval_Status__c,
        'Rejected'
      );
      Assert.areEqual(0, repriced.Agreed_Discount__c, 'Discount removed');
      Assert.areEqual(
        7080,
        repriced.Agreed_Total__c,
        'Re-priced at full price'
      );
      Assert.areEqual(
        0,
        [
            SELECT SUM(Discount_Amount__c) total
            FROM Enrolment_Fee_Line__c
            WHERE Enrolment__c = :rejectedId
          ][0]
          .get('total'),
        'Lines re-snapshotted'
      );
      try {
        EnrolmentController.decideDiscount(rejectedId, true);
        Assert.fail('Nothing pending anymore');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('no discount waiting'),
          e.getMessage()
        );
      }
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CourseOfferingParticipant
        WHERE Discount_Approval_Status__c = 'Approved'
      ],
      'One approved'
    );
  }

  @IsTest
  static void withdrawalReleasesTheSeat() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(1);
      Id enrolmentId = EnrolmentService.enrol(
          request(f.learners[0].Id, f.offering.Id, null)
        )
        .enrolmentId;
      Assert.areEqual(
        'Full',
        [SELECT Class_Status__c FROM CourseOffering WHERE Id = :f.offering.Id]
        .Class_Status__c,
        'Full'
      );
      try {
        EnrolmentController.withdraw(enrolmentId, null, null);
        Assert.fail('Reason required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      EnrolmentController.withdraw(
        enrolmentId,
        'Moved city',
        Date.today().addDays(-365)
      );
      CourseOfferingParticipant withdrawn = [
        SELECT ParticipationStatus, EndDate, StartDate, Withdrawal_Reason__c
        FROM CourseOfferingParticipant
        WHERE Id = :enrolmentId
      ];
      Assert.areEqual('Withdrew', withdrawn.ParticipationStatus, 'Withdrawn');
      Assert.areEqual(
        withdrawn.StartDate,
        withdrawn.EndDate,
        'Effective date clamped to start'
      );
      CourseOffering reopened = [
        SELECT Class_Status__c, Seats_Taken__c
        FROM CourseOffering
        WHERE Id = :f.offering.Id
      ];
      Assert.areEqual(
        'Open',
        reopened.Class_Status__c,
        'Seat released, class reopened'
      );
      Assert.areEqual(0, reopened.Seats_Taken__c, 'Seat count released');
      try {
        EnrolmentService.withdraw(enrolmentId, 'Again', null);
        Assert.fail('Already withdrawn');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('active'), e.getMessage());
      }
      Database.SaveResult invalid = Database.update(
        new CourseOffering(Id = f.offering.Id, Class_Status__c = 'Completed'),
        false
      );
      Assert.isFalse(
        invalid.isSuccess(),
        'Open to Completed is not an allowed class transition'
      );
    }
  }

  @IsTest
  static void rosterAndLookupsForTheUi() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(3);
      EnrolmentService.enrol(request(f.learners[0].Id, f.offering.Id, null));
      EnrolmentController.Roster roster = EnrolmentController.getRoster(
        f.offering.Id
      );
      Assert.areEqual(1, roster.rows.size(), 'One learner on the roster');
      Assert.areEqual(1, roster.seatsTaken, 'Seat counted on roster');
      Assert.areEqual(
        1,
        EnrolmentController.getEnrollableClasses(f.course.Id, f.branch.Id)
          .size(),
        'Open class listed'
      );
      Assert.areEqual(
        3,
        EnrolmentController.searchLearners('Enrol').size(),
        'Learners searchable'
      );
      try {
        EnrolmentController.getRoster(
          TestUtil.fakeId(CourseOffering.SObjectType)
        );
        Assert.fail('Unknown class');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Not found');
      }
    }
  }

  @IsTest
  static void counsellorEnrolsLearners() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture(3);
      User counsellor = TestDataFactory.createCounsellor(f.branch.Id);
      System.runAs(counsellor) {
        EnrolmentService.EnrolmentResult result = EnrolmentController.enrol(
          request(f.learners[0].Id, f.offering.Id, null)
        );
        Assert.areEqual(
          7080,
          result.quote.grandTotal,
          'Counsellor sees the agreed total'
        );
        Assert.areEqual(
          1,
          EnrolmentController.getRoster(f.offering.Id).rows.size(),
          'Counsellor sees the roster'
        );
      }
    }
  }
}
