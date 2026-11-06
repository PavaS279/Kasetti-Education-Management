@IsTest
private class CollegeSetupControllerTest {
  private static User systemAdministrator() {
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      Alias = ('s' + key).left(8),
      Email = 'kem.sa' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Admin ' + key,
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_IN',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator']
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'kem.sa' + key + '@kasetti.test'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      TestDataFactory.assignEducationLicense(u.Id);
      TestDataFactory.assignPermissionSets(
        u.Id,
        TestDataFactory.persona('KEM_Administrator')
      );
    }
    return u;
  }

  private static Id activeRule(CollegeTestFactory.Fixture f) {
    Admission_Rule__c rule = new Admission_Rule__c(
      Branch__c = f.branch.Id,
      Campus__c = f.campus.Id,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Status__c = 'Draft',
      Entry_Year_Of_Study__c = 1,
      Qualifying_Level__c = 'PUC',
      Qualifying_Streams__c = 'Science',
      Min_Percentage__c = 60,
      Entrance_Required__c = true
    );
    insert rule;
    insert new Admission_Rule_Entrance__c(
      Admission_Rule__c = rule.Id,
      Entrance_Exam__c = 'KCET',
      Max_Rank__c = 50000
    );
    AdmissionRuleService.activate(rule.Id);
    return rule.Id;
  }

  @IsTest
  static void administratorChangesSeatsAndCutOffs() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    Id ruleId;
    System.runAs(f.dean) {
      ruleId = activeRule(f);
    }
    User admin = systemAdministrator();
    Test.startTest();
    System.runAs(admin) {
      CollegeSetupController.Setup view = CollegeSetupController.getSetup();
      Assert.isTrue(view.canEdit);
      CollegeSetupController.Row row;
      for (CollegeSetupController.Row r : view.rows) {
        if (r.id == f.intake.Id) {
          row = r;
        }
      }
      Assert.isNotNull(row, 'The college intake is listed');
      Assert.areEqual(ruleId, row.regularRule.ruleId);
      Assert.areEqual(60, row.regularRule.minPercentage);
      Assert.isFalse(row.regularRule.allCampuses);

      CollegeSetupController.IntakeChange change = new CollegeSetupController.IntakeChange();
      change.id = f.intake.Id;
      change.intakeRegular = 8;
      change.intakeLateral = 1;
      change.admissionsOpen = true;
      change.deanExceptionsAllowed = false;
      CollegeSetupController.saveIntake(change);

      change.intakeRegular = 1.5;
      try {
        CollegeSetupController.saveIntake(change);
        Assert.fail('Seats are whole numbers');
      } catch (AuraHandledException e) {
        Assert.isTrue(true);
      }

      CollegeSetupController.RuleChange ruleChange = new CollegeSetupController.RuleChange();
      ruleChange.ruleId = ruleId;
      ruleChange.minPercentage = 65.5;
      CollegeSetupController.Entrance kcet = new CollegeSetupController.Entrance();
      kcet.exam = 'KCET';
      kcet.maxRank = 30000;
      ruleChange.entrances = new List<CollegeSetupController.Entrance>{ kcet };
      CollegeSetupController.saveRule(ruleChange);
    }
    Test.stopTest();
    Campus_Branch__c intake = [
      SELECT Intake_Regular__c, Intake_Lateral__c, Dean_Exceptions_Allowed__c
      FROM Campus_Branch__c
      WHERE Id = :f.intake.Id
    ];
    Assert.areEqual(8, intake.Intake_Regular__c);
    Assert.isFalse(intake.Dean_Exceptions_Allowed__c);
    Admission_Rule__c newer = [
      SELECT
        Min_Percentage__c,
        Status__c,
        (SELECT Max_Rank__c FROM Accepted_Entrances__r)
      FROM Admission_Rule__c
      WHERE Campus__c = :f.campus.Id AND Status__c = 'Active'
    ];
    Assert.areEqual(65.5, newer.Min_Percentage__c);
    Assert.areEqual(30000, newer.Accepted_Entrances__r[0].Max_Rank__c);
    Assert.areEqual(
      'Superseded',
      [SELECT Status__c FROM Admission_Rule__c WHERE Id = :ruleId].Status__c,
      'The earlier version stays on record'
    );
  }

  @IsTest
  static void staffViewButCannotChange() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    User desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    System.runAs(desk) {
      CollegeSetupController.Setup view = CollegeSetupController.getSetup();
      Assert.isFalse(view.canEdit);
      Assert.isFalse(view.rows.isEmpty());
      CollegeSetupController.IntakeChange change = new CollegeSetupController.IntakeChange();
      change.id = f.intake.Id;
      change.intakeRegular = 99;
      change.intakeLateral = 0;
      try {
        CollegeSetupController.saveIntake(change);
        Assert.fail('Only a System Administrator');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('System Administrator'));
      }
    }
    User teacher = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Teacher', 'KEM_Teacher_Edu' }
    );
    System.runAs(teacher) {
      try {
        CollegeSetupController.getSetup();
        Assert.fail('Not college staff');
      } catch (AuraHandledException e) {
        Assert.isTrue(true);
      }
    }
  }

  @IsTest
  static void exceptionsSwitchedOffBlockTheRequest() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    update new Campus_Branch__c(
      Id = f.intake.Id,
      Dean_Exceptions_Allowed__c = false
    );
    update new IndividualApplication(
      Id = f.admission.Id,
      College_Stage__c = 'Documents Verified',
      Eligibility_Status__c = 'Not Eligible',
      Interview_Outcome__c = null
    );
    System.runAs(f.dean) {
      try {
        InterviewService.requestException(f.admission.Id, 'Please');
        Assert.fail('Exceptions are off for this branch');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('switched off'));
      }
    }
  }
}
