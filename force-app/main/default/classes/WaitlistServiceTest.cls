@IsTest
private class WaitlistServiceTest {
  private class Fixture {
    CourseOffering offering;
    List<Account> learners = new List<Account>();
    Id firstEnrolmentId;
  }

  /** A one-seat class with one learner enrolled and four more learners. */
  private static Fixture fixture() {
    Fixture f = new Fixture();
    Branch__c branch = TestDataFactory.createBranch();
    LearningCourse course = TestDataFactory.createCourse('Robotics');
    insert new Fee_Price__c(
      Learning_Course__c = course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = 3000,
      Effective_From__c = Date.today().addDays(-1)
    );
    f.offering = TestDataFactory.createOffering(course.Id, branch.Id, 1);
    for (Integer i = 0; i < 5; i++) {
      f.learners.add(
        PersonAccountService.buildPerson(
          'W' + i,
          'Wait' + i + Crypto.getRandomInteger(),
          null,
          null,
          branch.Id,
          'Learner'
        )
      );
    }
    insert f.learners;
    f.firstEnrolmentId = enrol(f.learners[0].Id, f.offering.Id);
    return f;
  }

  private static Id enrol(Id learnerId, Id offeringId) {
    EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
    r.learnerAccountId = learnerId;
    r.offeringId = offeringId;
    return EnrolmentService.enrol(r).enrolmentId;
  }

  private static Id join(Fixture f, Integer index, Integer priority) {
    WaitlistService.JoinRequest r = new WaitlistService.JoinRequest();
    r.learnerAccountId = f.learners[index].Id;
    r.offeringId = f.offering.Id;
    r.priority = priority;
    return WaitlistController.joinWaitlist(r);
  }

  private static Waitlist_Entry__c entry(Id entryId) {
    return [
      SELECT Status__c, Offer_Expires__c, Offers_Made__c, Enrolment__c, Notes__c
      FROM Waitlist_Entry__c
      WHERE Id = :entryId
    ];
  }

  private static CourseOffering cls(Id offeringId) {
    return [
      SELECT
        Class_Status__c,
        Seats_Taken__c,
        Seats_Reserved__c,
        Seats_Available__c,
        Waitlist_Count__c
      FROM CourseOffering
      WHERE Id = :offeringId
    ];
  }

  @IsTest
  static void freedSeatGoesToTheNextLearnerAndIsHeld() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      // Fresh limits for the waitlist operations (set-up is its own transaction in use).
      Test.startTest();
      Assert.areEqual(
        'Full',
        cls(f.offering.Id).Class_Status__c,
        'One seat, taken'
      );
      Id normal = join(f, 1, 0);
      Id sibling = join(f, 2, 1);
      Assert.areEqual(2, cls(f.offering.Id).Waitlist_Count__c, 'Two waiting');

      WaitlistService.Waitlist view = WaitlistController.getWaitlist(
        f.offering.Id
      );
      Assert.areEqual(sibling, view.entries[0].id, 'Higher priority first');
      Assert.areEqual(1, view.entries[0].position, 'Position 1');
      Assert.areEqual(2, view.entries[1].position, 'Position 2');
      Assert.isTrue(view.canManage, 'Administrator manages waitlists');

      EnrolmentService.withdraw(f.firstEnrolmentId, 'Moved city', null);
      Waitlist_Entry__c offered = entry(sibling);
      Assert.areEqual('Offered', offered.Status__c, 'Seat offered by priority');
      Assert.isTrue(
        offered.Offer_Expires__c > System.now().addHours(47),
        '48-hour hold'
      );
      Assert.areEqual(1, offered.Offers_Made__c, 'Offer counted');
      Assert.areEqual('Waiting', entry(normal).Status__c, 'Still waiting');
      CourseOffering held = cls(f.offering.Id);
      Assert.areEqual(1, held.Seats_Reserved__c, 'Seat held');
      Assert.areEqual(0, held.Seats_Available__c, 'Not available to others');
      Assert.areEqual('Full', held.Class_Status__c, 'Still full while held');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Task
          WHERE WhatId = :sibling AND Priority = 'High'
        ],
        'Follow-up task for the counsellor'
      );
      try {
        enrol(f.learners[3].Id, f.offering.Id);
        Assert.fail('The held seat is not available to others');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('full'), e.getMessage());
      }

      Id enrolmentId = WaitlistController.acceptOffer(sibling);
      Waitlist_Entry__c accepted = entry(sibling);
      Assert.areEqual('Enrolled', accepted.Status__c, 'Enrolled from waitlist');
      Assert.areEqual(enrolmentId, accepted.Enrolment__c, 'Linked enrolment');
      CourseOffering after = cls(f.offering.Id);
      Assert.areEqual(1, after.Seats_Taken__c, 'Seat taken');
      Assert.areEqual(0, after.Seats_Reserved__c, 'Hold released');
      Assert.areEqual(1, after.Waitlist_Count__c, 'One still waiting');
      Assert.areEqual(
        1,
        WaitlistController.getLearnerWaitlist(f.learners[1].Id)[0].position,
        'Remaining learner is first in line'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void capacityIncreaseDeclineAndExpiry() {
    // Fifteen waitlist operations in one transaction: notifications are covered
    // by MessageServiceTest and would only add queries here.
    MessageService.disabled = true;
    IntegrationService.disabled = true;
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      // Fresh limits for the waitlist operations (set-up is its own transaction in use).
      Test.startTest();
      Id first = join(f, 1, 0);
      Id second = join(f, 2, 0);
      Id third = join(f, 3, 0);

      update new CourseOffering(Id = f.offering.Id, EnrollmentCapacity = 2);
      Assert.areEqual('Offered', entry(first).Status__c, 'Extra seat offered');
      Assert.areEqual('Waiting', entry(second).Status__c, 'Next waits');

      WaitlistController.declineOffer(first, 'Timing does not suit');
      Waitlist_Entry__c declined = entry(first);
      Assert.areEqual('Declined', declined.Status__c, 'Declined');
      Assert.isTrue(declined.Notes__c.contains('Timing'), 'Reason kept');
      Assert.areEqual('Offered', entry(second).Status__c, 'Seat passed on');

      Database.update(
        new Waitlist_Entry__c(
          Id = second,
          Offer_Expires__c = System.now().addMinutes(-1)
        ),
        AccessLevel.SYSTEM_MODE
      );
      try {
        WaitlistService.accept(second);
        Assert.fail('Expired offers cannot be accepted');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('expired'), e.getMessage());
      }
      new WaitlistOfferJob().execute(null);
      Assert.areEqual('Expired', entry(second).Status__c, 'Expired by the job');
      Assert.areEqual(
        'Offered',
        entry(third).Status__c,
        'Seat passed on again'
      );

      WaitlistController.requeue(first);
      Assert.areEqual('Waiting', entry(first).Status__c, 'Back in the queue');
      WaitlistController.removeFromWaitlist(third, 'Family changed their mind');
      Assert.areEqual('Cancelled', entry(third).Status__c, 'Removed');
      Assert.areEqual(
        'Offered',
        entry(first).Status__c,
        'Requeued learner gets the seat'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void guardsJoining() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    Fixture f;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
      join(f, 1, 0);
      for (Integer i : new List<Integer>{ 0, 1 }) {
        try {
          join(f, i, 0);
          Assert.fail('Duplicate or enrolled learner');
        } catch (AuraHandledException e) {
          Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
        }
      }
      CourseOffering open = TestDataFactory.createOffering(
        [SELECT LearningCourseId FROM CourseOffering WHERE Id = :f.offering.Id]
        .LearningCourseId,
        [SELECT Branch__c FROM CourseOffering WHERE Id = :f.offering.Id]
        .Branch__c,
        5
      );
      WaitlistService.JoinRequest r = new WaitlistService.JoinRequest();
      r.learnerAccountId = f.learners[2].Id;
      r.offeringId = open.Id;
      try {
        WaitlistService.join(r);
        Assert.fail('Seats are free');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('enrol the learner directly'),
          e.getMessage()
        );
      }
      Assert.areEqual(
        0,
        WaitlistService.offerNext(new Set<Id>{ open.Id }),
        'Nobody waiting'
      );
      Assert.isTrue(
        KemJobs.jobFor('KEM Waitlist Offers') instanceof WaitlistOfferJob,
        'Job registered'
      );
    }
    System.runAs(teacher) {
      WaitlistService.JoinRequest r = new WaitlistService.JoinRequest();
      r.learnerAccountId = f.learners[3].Id;
      r.offeringId = f.offering.Id;
      try {
        WaitlistService.join(r);
        Assert.fail('Teachers do not manage waitlists');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
  }

  @IsTest
  static void controllerReportsErrors() {
    System.runAs(TestDataFactory.admin()) {
      Id missing = TestUtil.fakeId(Waitlist_Entry__c.SObjectType);
      Integer failures = 0;
      for (Integer i = 0; i < 6; i++) {
        try {
          switch on i {
            when 0 {
              WaitlistController.acceptOffer(missing);
            }
            when 1 {
              WaitlistController.declineOffer(missing, 'x');
            }
            when 2 {
              WaitlistController.removeFromWaitlist(missing, null);
            }
            when 3 {
              WaitlistController.requeue(missing);
            }
            when 4 {
              WaitlistController.joinWaitlist(
                new WaitlistService.JoinRequest()
              );
            }
            when 5 {
              WaitlistController.getWaitlist(
                TestUtil.fakeId(CourseOffering.SObjectType)
              );
            }
          }
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Assert.areEqual(6, failures, 'Every call reports a friendly error');
      Assert.isTrue(
        WaitlistController.getLearnerWaitlist(
            TestUtil.fakeId(Account.SObjectType)
          )
          .isEmpty(),
        'No entries'
      );
    }
  }
}
