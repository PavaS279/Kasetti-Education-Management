@IsTest
private class CollegePublicControllerTest {
  @TestSetup
  static void setup() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 7);
    System.runAs(fixture.dean) {
      Admission_Rule__c rule = new Admission_Rule__c(
        Branch__c = fixture.branch.Id,
        Academic_Year__c = '2026-27',
        Entry_Route__c = 'Regular',
        Status__c = 'Draft',
        Entry_Year_Of_Study__c = 1,
        Qualifying_Level__c = 'SSLC',
        Min_Percentage__c = 80,
        Entrance_Required__c = false,
        Interview_Required__c = true
      );
      insert rule;
      AdmissionRuleService.activate(rule.Id);
    }
  }

  private static User guest() {
    List<User> guests = [
      SELECT Id
      FROM User
      WHERE UserType = 'Guest' AND IsActive = TRUE
      LIMIT 1
    ];
    return guests.isEmpty() ? new User(Id = UserInfo.getUserId()) : guests[0];
  }

  private static CollegeAdmissionController.Qualification sslc(
    Decimal percentage
  ) {
    CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
    q.level = 'SSLC';
    q.percentage = percentage;
    return q;
  }

  @IsTest
  static void visitorSeesPublishedInformationAndChecksEligibility() {
    Id intakeId = [SELECT Id FROM Campus_Branch__c LIMIT 1].Id;
    Integer admissions = [SELECT COUNT() FROM IndividualApplication];
    System.runAs(guest()) {
      Test.startTest();
      List<CollegeAdmissionController.CampusChoice> catalogue = CollegePublicController.getCatalogue();
      System.assertEquals(1, catalogue.size());
      CollegeAdmissionController.BranchChoice branch = catalogue[0]
        .programmes[0]
        .branches[0];
      System.assertEquals(
        null,
        branch.seatsRegular,
        'Seat counts are not published'
      );
      System.assertNotEquals(null, catalogue[0].code);
      System.assertNotEquals(null, branch.externalId);
      CollegeAdmissionController.Requirements needs = CollegePublicController.getRequirements(
        intakeId,
        'Regular'
      );
      System.assert(needs.open);
      System.assertEquals(null, needs.seatsLeft);
      AdmissionEligibilityService.Preview refused = CollegePublicController.checkEligibility(
        intakeId,
        'Regular',
        new List<CollegeAdmissionController.Qualification>{ sslc(70) },
        null
      );
      AdmissionEligibilityService.Preview accepted = CollegePublicController.checkEligibility(
        intakeId,
        'Regular',
        new List<CollegeAdmissionController.Qualification>{ sslc(85) },
        null
      );
      Test.stopTest();
      System.assertEquals('Not Eligible', refused.status);
      System.assertEquals('Eligible', accepted.status);
    }
    System.assertEquals(
      admissions,
      [SELECT COUNT() FROM IndividualApplication],
      'Nothing is saved'
    );
  }

  @IsTest
  static void inputsAreValidatedOnTheServer() {
    Id intakeId = [SELECT Id FROM Campus_Branch__c LIMIT 1].Id;
    Integer refused = 0;
    System.runAs(guest()) {
      Test.startTest();
      try {
        CollegePublicController.getRequirements(intakeId, 'Backdoor');
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegePublicController.checkEligibility(
          intakeId,
          'Regular',
          new List<CollegeAdmissionController.Qualification>{ sslc(140) },
          null
        );
      } catch (AuraHandledException expected) {
        refused++;
      }
      CollegeAdmissionController.Entrance bad = new CollegeAdmissionController.Entrance();
      bad.exam = 'JEE';
      bad.rank = 10;
      try {
        CollegePublicController.checkEligibility(
          intakeId,
          'Regular',
          new List<CollegeAdmissionController.Qualification>{ sslc(80) },
          new List<CollegeAdmissionController.Entrance>{ bad }
        );
      } catch (AuraHandledException expected) {
        refused++;
      }
      Test.stopTest();
    }
    update new Campus_Branch__c(Id = intakeId, Admissions_Open__c = false);
    System.runAs(guest()) {
      try {
        CollegePublicController.getRequirements(intakeId, 'Regular');
      } catch (AuraHandledException expected) {
        refused++;
      }
    }
    System.assertEquals(4, refused);
  }
}
