@IsTest
private class InterviewServiceTest {
  @IsTest
  static void deanSchedulesAndRecordsOutcomeWithLifecycleGuards() {
    User dean = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Administrator',
        'KEM_Administrator_Edu',
        'KEM_College_Dean'
      }
    );
    User unauthorised = TestDataFactory.createUser(new List<String>());
    System.runAs(dean) {
      IndividualApplication admission = admission();
      Datetime futureInterview = System.now().addDays(1);
      InterviewService.schedule(admission.Id, futureInterview, dean.Id);
      admission = interview(admission.Id);
      System.assertEquals('Interview Scheduled', admission.College_Stage__c);
      System.assertEquals(futureInterview, admission.Interview_Date__c);
      System.assertEquals(dean.Id, admission.Interviewer__c);

      try {
        InterviewService.recordOutcome(admission.Id, 'Pass', 'Good fit');
        System.assert(
          false,
          'Expected a future interview to reject an outcome.'
        );
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('only after'));
      }
      update new IndividualApplication(
        Id = admission.Id,
        Interview_Date__c = System.now().addHours(-1)
      );
      InterviewService.recordOutcome(admission.Id, 'Pass', ' Good fit ');
      admission = interview(admission.Id);
      System.assertEquals('Ready For Decision', admission.College_Stage__c);
      System.assertEquals('Pass', admission.Interview_Outcome__c);
      System.assertEquals('Good fit', admission.Interview_Remarks__c);

      try {
        InterviewService.schedule(
          admission.Id,
          System.now().addDays(2),
          dean.Id
        );
        System.assert(
          false,
          'Expected re-scheduling from the wrong stage to fail.'
        );
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('Verify'));
      }
    }
    System.runAs(unauthorised) {
      try {
        InterviewService.schedule(
          null,
          System.now().addDays(1),
          unauthorised.Id
        );
        System.assert(false, 'Expected interview permission to be required.');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('permission'));
      }
    }
  }

  @IsTest
  static void validationRulesProtectDirectEdits() {
    User dean = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Administrator',
        'KEM_Administrator_Edu',
        'KEM_College_Dean'
      }
    );
    System.runAs(dean) {
      IndividualApplication admission = admission();
      Database.SaveResult missingDetails = Database.update(
        new IndividualApplication(
          Id = admission.Id,
          Interview_Outcome__c = 'Reject'
        ),
        false
      );
      System.assertEquals(false, missingDetails.isSuccess());
      System.assert(
        missingDetails.getErrors()[0].getMessage().contains('requires')
      );
      Database.SaveResult futureOutcome = Database.update(
        new IndividualApplication(
          Id = admission.Id,
          Interview_Date__c = System.now().addDays(1),
          Interviewer__c = dean.Id,
          Interview_Outcome__c = 'Pass'
        ),
        false
      );
      System.assertEquals(false, futureOutcome.isSuccess());
      System.assert(
        futureOutcome.getErrors()[0].getMessage().contains('future')
      );
    }
  }

  private static IndividualApplication admission() {
    Learning learning = new Learning(
      Name = TestDataFactory.unique('Interview Programme'),
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram programme = new LearningProgram(
      Name = learning.Name,
      LearningId = learning.Id,
      Programme_Code__c = 'I',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert programme;
    Branch__c campus = TestDataFactory.createBranch();
    Account learner = PersonAccountService.buildPerson(
      'Interview',
      TestDataFactory.unique('Applicant'),
      null,
      null,
      campus.Id,
      'Learner'
    );
    insert learner;
    learner = [SELECT Id, PersonContactId FROM Account WHERE Id = :learner.Id];
    IndividualApplication value = new IndividualApplication(
      Category = 'Education',
      AccountId = learner.Id,
      ContactId = learner.PersonContactId,
      Status = 'Processing',
      Branch__c = campus.Id,
      College_Mode__c = true,
      College_Stage__c = 'Documents Verified',
      Learning_Program__c = programme.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1
    );
    insert value;
    return value;
  }

  private static IndividualApplication interview(Id applicationId) {
    return [
      SELECT
        College_Stage__c,
        Interview_Date__c,
        Interviewer__c,
        Interview_Outcome__c,
        Interview_Remarks__c
      FROM IndividualApplication
      WHERE Id = :applicationId
    ];
  }
}
