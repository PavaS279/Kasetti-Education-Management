@IsTest
private class ReferralTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'REF-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Referral Art');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 4000,
        Effective_From__c = Date.today().addDays(-30)
      );
      TestDataFactory.createOffering(course.Id, branch.Id, 10);
      insert new List<Account>{
        PersonAccountService.buildPerson(
          'Priya',
          'Refer',
          'priya.refer@example.com',
          null,
          branch.Id,
          'Guardian'
        ),
        PersonAccountService.buildPerson(
          'Nikhil',
          'Newjoin',
          null,
          null,
          branch.Id,
          'Learner'
        ),
        PersonAccountService.buildPerson(
          'Olga',
          'Oldtimer',
          null,
          null,
          branch.Id,
          'Learner'
        )
      };
    }
  }

  private static Account person(String first) {
    return [
      SELECT Id, PersonContactId, Referral_Code__c, Alumni__c, Alumni_Since__c
      FROM Account
      WHERE FirstName = :first
    ];
  }

  private static Id enrol(String first) {
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = person(first).Id;
    request.offeringId = [
      SELECT Id
      FROM CourseOffering
      WHERE LearningCourse.Name = 'Referral Art'
      LIMIT 1
    ]
    .Id;
    return EnrolmentService.enrol(request).enrolmentId;
  }

  /** A referred enquiry converted to the given learner. */
  private static Lead referredEnquiry(String code, String learnerFirst) {
    Lead l = TestDataFactory.buildEnquiry(
      [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'REF-01'].Id
    );
    l.Referral_Code__c = code;
    insert l;
    // Conversion links the enquiry to its learner (EnquiryConversionService).
    Database.update(
      new Lead(Id = l.Id, Converted_Learner__c = person(learnerFirst).Id),
      AccessLevel.SYSTEM_MODE
    );
    return [
      SELECT Id, Referred_By__c, Enquiry_Channel__c, Referral_Code__c
      FROM Lead
      WHERE Id = :l.Id
    ];
  }

  @IsTest
  static void aCodeAddedAfterSavingLinksTheReferrer() {
    System.runAs(TestDataFactory.admin()) {
      String code = ReferralService.codeFor(person('Priya').Id);
      Lead l = TestDataFactory.buildEnquiry(
        [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'REF-01'].Id
      );
      insert l;
      Test.startTest();
      update new Lead(Id = l.Id, Referral_Code__c = code.toLowerCase());
      Test.stopTest();
      Lead saved = [
        SELECT Referred_By__c, Enquiry_Channel__c, Referral_Code__c
        FROM Lead
        WHERE Id = :l.Id
      ];
      Assert.areEqual(
        person('Priya').Id,
        saved.Referred_By__c,
        'Referrer linked'
      );
      Assert.areEqual('Referral', saved.Enquiry_Channel__c, 'Channel');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Referral__c WHERE Enquiry__c = :l.Id],
        'Referral recorded once'
      );
      // Editing the enquiry again does not record a second referral.
      update new Lead(Id = l.Id, Description = 'Called back');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Referral__c WHERE Enquiry__c = :l.Id],
        'Still one'
      );
    }
  }

  @IsTest
  static void codesAreCreatedOnceAndReadable() {
    System.runAs(TestDataFactory.admin()) {
      String code = ReferralController.referralCode(person('Priya').Id);
      Assert.isTrue(Pattern.matches('REF-[A-HJ-NP-Z2-9]{4}', code), code);
      Assert.areEqual(
        code,
        ReferralService.codeFor(person('Priya').Id),
        'Same code next time'
      );
      Assert.areEqual(code, person('Priya').Referral_Code__c, 'Stored');
      Assert.areEqual(
        'AB-12',
        ReferralService.normalise(' ab - 12 '.replace(' ', '')),
        'Normalised'
      );
      Assert.isNull(ReferralService.normalise('  '), 'Blank');
    }
  }

  @IsTest
  static void referralIsTrackedToEnrolmentAndRewarded() {
    System.runAs(TestDataFactory.admin()) {
      String code = ReferralService.codeFor(person('Priya').Id);
      Lead enquiry = referredEnquiry('  ' + code.toLowerCase() + ' ', 'Nikhil');
      Assert.areEqual(
        person('Priya').Id,
        enquiry.Referred_By__c,
        'Referrer linked'
      );
      Assert.areEqual('Referral', enquiry.Enquiry_Channel__c, 'Channel');
      Assert.areEqual(code, enquiry.Referral_Code__c, 'Code tidied');
      Referral__c r = [
        SELECT Id, Status__c, Branch__c
        FROM Referral__c
        WHERE Enquiry__c = :enquiry.Id
      ];
      Assert.areEqual('Enquired', r.Status__c, 'Recorded');

      Test.startTest();
      Id enrolmentId = enrol('Nikhil');
      r = [
        SELECT Status__c, Enrolment__c, Referred_Learner__c, Enrolled_On__c
        FROM Referral__c
        WHERE Id = :r.Id
      ];
      Assert.areEqual('Enrolled', r.Status__c, 'Enrolled');
      Assert.areEqual(enrolmentId, r.Enrolment__c, 'First enrolment');
      Assert.areEqual(person('Nikhil').Id, r.Referred_Learner__c, 'Learner');

      ReferralService.Desk desk = ReferralController.getDesk(null);
      Assert.isTrue(desk.canReward, 'Finance can reward');
      Assert.areEqual('Manual', desk.rewardMode, 'Manual by default');
      Assert.areEqual(1, desk.counts.get('Enrolled'), 'Counted');

      Id noteId = ReferralController.grantReward(r.Id);
      Test.stopTest();
      Credit_Note__c note = [
        SELECT Amount__c, Origin__c, Bill_To__c, Status__c
        FROM Credit_Note__c
        WHERE Id = :noteId
      ];
      Assert.areEqual(500, note.Amount__c, 'Reward amount');
      Assert.areEqual('Referral', note.Origin__c, 'Origin');
      Assert.areEqual(
        person('Priya').PersonContactId,
        note.Bill_To__c,
        'Credit for the referrer'
      );
      Assert.areEqual(
        'Rewarded',
        [SELECT Status__c FROM Referral__c WHERE Id = :r.Id].Status__c,
        'Rewarded'
      );
      try {
        ReferralService.reward(r.Id, false);
        Assert.fail('Once only');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already been rewarded'),
          e.getMessage()
        );
      }
      desk = ReferralService.desk(null);
      Assert.areEqual(1, desk.topReferrers.size(), 'Top referrer');
      Assert.areEqual(1, desk.topReferrers[0].enrolled, 'One joined');
      Assert.isTrue(
        desk.conversionRate == 100,
        'All converted: ' + desk.conversionRate
      );
      Assert.areEqual(1, desk.referrals.size(), 'Listed');

      PortalService.ReferralInfo info = PortalService.referralFor(
        person('Priya').PersonContactId,
        false
      );
      Assert.areEqual(code, info.code, 'Code in the portal');
      Assert.areEqual(1, info.referred, 'Referred');
      Assert.areEqual(1, info.joined, 'Joined');
      Assert.isTrue(info.rewardsOn, 'Rewards on');
    }
  }

  @IsTest
  static void autoModeRewardsOnEnrolment() {
    AppSettings.overrides.put('Referral_Reward_Mode', 'Auto');
    AppSettings.overrides.put('Referral_Reward_Amount', '750');
    System.runAs(TestDataFactory.admin()) {
      String code = ReferralService.codeFor(person('Priya').Id);
      Lead enquiry = referredEnquiry(code, 'Nikhil');
      Test.startTest();
      enrol('Nikhil');
      Test.stopTest();
      Referral__c r = [
        SELECT Status__c, Reward_Amount__c, Credit_Note__c
        FROM Referral__c
        WHERE Enquiry__c = :enquiry.Id
      ];
      Assert.areEqual('Rewarded', r.Status__c, 'Rewarded automatically');
      Assert.areEqual(750, r.Reward_Amount__c, 'Configured amount');
      Assert.isNotNull(r.Credit_Note__c, 'Credit note');
    }
  }

  @IsTest
  static void unknownCodesOffModeAndNotEligible() {
    AppSettings.overrides.put('Referral_Reward_Mode', 'Off');
    System.runAs(TestDataFactory.admin()) {
      Lead unknown = referredEnquiry('NOPE-0000', 'Olga');
      Assert.isNull(unknown.Referred_By__c, 'Unknown code: no referrer');
      Assert.areEqual(0, [SELECT COUNT() FROM Referral__c], 'No referral');

      String code = ReferralService.codeFor(person('Priya').Id);
      Lead enquiry = referredEnquiry(code, 'Nikhil');
      enrol('Nikhil');
      Referral__c r = [
        SELECT Id
        FROM Referral__c
        WHERE Enquiry__c = :enquiry.Id
      ];
      Assert.isFalse(ReferralService.desk(null).canReward, 'Rewards off');
      try {
        ReferralService.reward(r.Id, false);
        Assert.fail('Off');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('switched off'), e.getMessage());
      }
      ReferralController.markNotEligible(r.Id, 'Sibling already enrolled');
      Referral__c after = [
        SELECT Status__c, Notes__c
        FROM Referral__c
        WHERE Id = :r.Id
      ];
      Assert.areEqual('Not Eligible', after.Status__c, 'Marked');
      Assert.areEqual('Sibling already enrolled', after.Notes__c, 'Note');
    }
  }

  @IsTest
  static void completingTheLastClassMakesAnAlumnus() {
    System.runAs(TestDataFactory.admin()) {
      Id olga = enrol('Olga');
      Test.startTest();
      update new CourseOfferingParticipant(
        Id = olga,
        ParticipationStatus = 'Completed'
      );
      Account alumnus = person('Olga');
      Assert.isTrue(alumnus.Alumni__c, 'Alumnus');
      Assert.areEqual(Date.today(), alumnus.Alumni_Since__c, 'Since today');
      ReferralService.Desk desk = ReferralService.desk(null);
      Assert.areEqual(1, desk.alumniTotal, 'Counted');
      Assert.areEqual('Olga Oldtimer', desk.alumni[0].name, 'Listed');
      Integer sent = ReferralController.inviteAlumni(
        new List<Id>{ alumnus.Id },
        'New robotics classes start in June.'
      );
      Test.stopTest();
      Assert.isTrue(sent >= 1, 'Invited: ' + sent);
      Assert.isNotNull(
        person('Olga').Referral_Code__c,
        'Code created for the invitation'
      );
      try {
        ReferralController.inviteAlumni(new List<Id>(), null);
        Assert.fail('Nobody chosen');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Choose'), e.getMessage());
      }
    }
  }

  @IsTest
  static void portalAndErrors() {
    System.runAs(TestDataFactory.admin()) {
      PortalService.viewerOverride = person('Priya').PersonContactId;
      PortalService.ReferralInfo before = PortalController.getReferral(false);
      Assert.isNull(before.code, 'No code until asked');
      PortalService.ReferralInfo after = PortalController.getReferral(true);
      Assert.isNotNull(after.code, 'Code created on request');
      Integer failures = 0;
      try {
        ReferralController.grantReward(null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        ReferralController.markNotEligible(null, null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        ReferralController.referralCode(null);
      } catch (AuraHandledException e) {
        failures++;
      }
      Assert.areEqual(3, failures, 'Errors reported');
      Assert.isNotNull(ReferralController.getDesk(null), 'Desk');
    }
  }
}
