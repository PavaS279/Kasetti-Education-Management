@IsTest
private class AdmissionEligibilityServiceTest {
  @IsTest
  static void campusRuleWinsAndEvidenceIsCaptured() {
    Fixture f = setupFixture(86, false);
    AdmissionEligibilityService.evaluate(f.applicationId);
    IndividualApplication result = application(f.applicationId);
    System.assertEquals('Not Eligible', result.Eligibility_Status__c);
    System.assertEquals(f.campusRuleId, result.Evaluated_Rule__c);
    System.assert(result.Eligibility_Notes__c.contains('90'));
    System.assert(result.Eligibility_Evidence__c.contains('qualificationId'));
    System.assertNotEquals(null, result.Eligibility_Evaluated_On__c);
    System.assertEquals(
      true,
      [SELECT Used__c FROM Admission_Rule__c WHERE Id = :f.campusRuleId].Used__c
    );
  }

  @IsTest
  static void entranceIsRequiredAndAnyAcceptedExamPasses() {
    Fixture f = setupFixture(92, true);
    AdmissionEligibilityService.evaluate(f.applicationId);
    System.assertEquals(
      'Not Checked',
      application(f.applicationId).Eligibility_Status__c
    );
    insert new Entrance_Score__c(
      Student__c = f.studentId,
      Exam__c = 'KCET',
      Exam_Year__c = 2026,
      Rank__c = 12400,
      Verified__c = true,
      Verified_By__c = UserInfo.getUserId(),
      Verified_On__c = System.now()
    );
    AdmissionEligibilityService.evaluate(f.applicationId);
    IndividualApplication result = application(f.applicationId);
    System.assertEquals('Eligible', result.Eligibility_Status__c);
    System.assert(result.Eligibility_Evidence__c.contains('KCET'));
    System.assert(result.Eligibility_Evidence__c.contains('12400'));
  }

  @IsTest
  static void noRuleAndDecisionFreezeAreEnforced() {
    Branch__c campus = TestDataFactory.createBranch();
    LearningCourse branch = TestDataFactory.createCourse(
      'Closed College Branch'
    );
    Account student = learner(campus.Id);
    IndividualApplication admission = admission(student, campus.Id, branch.Id);
    AdmissionEligibilityService.evaluate(admission.Id);
    System.assertEquals(
      'Not Eligible',
      application(admission.Id).Eligibility_Status__c
    );
    IndividualApplication frozen = new IndividualApplication(
      Category = 'Education',
      AccountId = student.Id,
      ContactId = student.PersonContactId,
      Status = 'Application Decision',
      Branch__c = campus.Id,
      Learning_Course__c = branch.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1
    );
    insert frozen;
    try {
      AdmissionEligibilityService.evaluate(frozen.Id);
      System.assert(false, 'Expected frozen evidence to reject re-evaluation.');
    } catch (AppException expected) {
      System.assert(expected.getMessage().contains('locked'));
    }
  }

  @IsTest
  static void verifiedQualificationChangeReevaluatesAdmission() {
    Fixture f = setupFixture(86, false);
    AdmissionEligibilityService.evaluate(f.applicationId);
    System.assertEquals(
      'Not Eligible',
      application(f.applicationId).Eligibility_Status__c
    );
    Test.startTest();
    update new Academic_Qualification__c(
      Id = f.qualificationId,
      Percentage__c = 92
    );
    Test.stopTest();
    System.assertEquals(
      'Eligible',
      application(f.applicationId).Eligibility_Status__c
    );
    new CollegeEligibilityReevaluationJob(new List<Id>{ f.applicationId })
      .execute(null);
    System.assertEquals(
      'Eligible',
      application(f.applicationId).Eligibility_Status__c
    );
  }

  private static Fixture setupFixture(
    Decimal percentage,
    Boolean entranceRequired
  ) {
    User admin = TestDataFactory.admin();
    Branch__c campus = TestDataFactory.createBranch();
    LearningCourse branch = TestDataFactory.createCourse('BE CSE');
    Account student = learner(campus.Id);
    IndividualApplication admission = admission(student, campus.Id, branch.Id);
    Academic_Qualification__c qualification = new Academic_Qualification__c(
      Student__c = student.Id,
      Level__c = 'PUC',
      Percentage__c = percentage,
      Stream_Group__c = 'Science',
      Completion_Year__c = 2026,
      Verified__c = true,
      Verified_By__c = UserInfo.getUserId(),
      Verified_On__c = System.now()
    );
    insert qualification;
    Admission_Rule__c allCampus = rule(branch.Id, null, 80, false);
    Admission_Rule__c campusSpecific = rule(
      branch.Id,
      campus.Id,
      90,
      entranceRequired
    );
    System.runAs(admin) {
      insert new List<Admission_Rule__c>{ allCampus, campusSpecific };
      if (entranceRequired) {
        insert new List<Admission_Rule_Entrance__c>{
          new Admission_Rule_Entrance__c(
            Admission_Rule__c = campusSpecific.Id,
            Entrance_Exam__c = 'KCET',
            Max_Rank__c = 20000,
            Exam_Year_From__c = 2025,
            Exam_Year_To__c = 2027
          ),
          new Admission_Rule_Entrance__c(
            Admission_Rule__c = campusSpecific.Id,
            Entrance_Exam__c = 'COMEDK',
            Max_Rank__c = 15000
          )
        };
      }
      AdmissionRuleService.activate(allCampus.Id);
      AdmissionRuleService.activate(campusSpecific.Id);
    }
    Fixture result = new Fixture();
    result.studentId = student.Id;
    result.applicationId = admission.Id;
    result.campusRuleId = campusSpecific.Id;
    result.qualificationId = qualification.Id;
    return result;
  }

  private static Account learner(Id campusId) {
    Account value = PersonAccountService.buildPerson(
      'College',
      'Applicant' + Crypto.getRandomInteger(),
      null,
      null,
      campusId,
      'Learner'
    );
    insert value;
    return [SELECT Id, PersonContactId FROM Account WHERE Id = :value.Id];
  }

  private static IndividualApplication admission(
    Account student,
    Id campusId,
    Id branchId
  ) {
    IndividualApplication value = new IndividualApplication(
      Category = 'Education',
      AccountId = student.Id,
      ContactId = student.PersonContactId,
      Status = 'Processing',
      Branch__c = campusId,
      Learning_Course__c = branchId,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1
    );
    insert value;
    return value;
  }

  private static Admission_Rule__c rule(
    Id branchId,
    Id campusId,
    Decimal minimum,
    Boolean entranceRequired
  ) {
    return new Admission_Rule__c(
      Branch__c = branchId,
      Campus__c = campusId,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Status__c = 'Draft',
      Entry_Year_Of_Study__c = 1,
      Qualifying_Level__c = 'PUC',
      Qualifying_Streams__c = 'Science',
      Min_Percentage__c = minimum,
      Entrance_Required__c = entranceRequired
    );
  }

  private static IndividualApplication application(Id applicationId) {
    return [
      SELECT
        Eligibility_Status__c,
        Eligibility_Notes__c,
        Evaluated_Rule__c,
        Eligibility_Evidence__c,
        Eligibility_Evaluated_On__c
      FROM IndividualApplication
      WHERE Id = :applicationId
    ];
  }

  private class Fixture {
    Id studentId;
    Id applicationId;
    Id campusRuleId;
    Id qualificationId;
  }
}
