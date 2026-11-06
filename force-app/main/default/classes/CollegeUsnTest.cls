@IsTest
private class CollegeUsnTest {
  private class Setup {
    CollegeTestFactory.Fixture fixture;
    Id first;
    Id second;
    String firstNumber;
    String secondNumber;
  }

  /** Two enrolled students at a campus with VTU codes 1 and KT (branch code AD, joined 2026). */
  private static Setup enrolTwo() {
    Setup s = new Setup();
    s.fixture = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    update new Branch__c(
      Id = s.fixture.campus.Id,
      VTU_Region_Code__c = '1',
      VTU_College_Code__c = 'KT'
    );
    // Enrolled students with enrolment numbers; the admit-and-pay story is
    // covered elsewhere and is too long to run twice here.
    IndividualApplication secondAdmission;
    System.runAs(s.fixture.dean) {
      secondAdmission = CollegeTestFactory.admission(s.fixture, 'Second');
    }
    s.firstNumber = 'KT26AAAD901';
    s.secondNumber = 'KT26AAAD902';
    List<Programme_Enrolment__c> rows = new List<Programme_Enrolment__c>();
    for (
      IndividualApplication a : new List<IndividualApplication>{
        s.fixture.admission,
        secondAdmission
      }
    ) {
      rows.add(
        new Programme_Enrolment__c(
          Student__c = a.AccountId,
          Programme__c = s.fixture.programme.Id,
          Branch__c = s.fixture.branch.Id,
          Campus__c = s.fixture.campus.Id,
          Campus_Branch__c = s.fixture.intake.Id,
          Application__c = a.Id,
          Entry_Route__c = 'Regular',
          Entry_Year_Of_Study__c = 1,
          Admission_Year__c = 2026,
          Academic_Year__c = '2026-27',
          Current_Year_Of_Study__c = 1,
          Status__c = 'Provisional',
          Payment_Due_By__c = Date.today().addDays(7)
        )
      );
    }
    insert rows;
    // Enrolled with an enrolment number (Provisional -> Enrolled is allowed).
    rows[0].Status__c = 'Enrolled';
    rows[0].Roll_Number__c = s.firstNumber;
    rows[1].Status__c = 'Enrolled';
    rows[1].Roll_Number__c = s.secondNumber;
    update rows;
    s.first = rows[0].Id;
    s.second = rows[1].Id;
    return s;
  }

  private static User systemAdministrator() {
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User u = new User(
      Alias = ('u' + key).left(8),
      Email = 'kem.usn' + key + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'USN Admin',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_IN',
      ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator']
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'kem.usn' + key + '@kasetti.test'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
    }
    return u;
  }

  private static String refusal(Id enrolmentId, String usn, String reason) {
    try {
      CollegeUsnService.setUsn(enrolmentId, usn, reason);
      return null;
    } catch (AppException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void staffEnterAUsnThatMatchesTheStudent() {
    Setup s = enrolTwo();
    System.runAs(s.fixture.dean) {
      Assert.isTrue(
        refusal(s.first, '1KT26A001', null).contains('10 characters')
      );
      Assert.isTrue(
        refusal(s.first, '2KT26AD001', null).contains('starts with')
      );
      Assert.isTrue(refusal(s.first, '1KT25AD001', null).contains('year'));
      Assert.isTrue(
        refusal(s.first, '1KT26CS001', null).contains('branch code')
      );
      CollegeStudentsController.setUsn(s.first, ' 1kt26ad001 ', null);
      Assert.isTrue(
        refusal(s.second, '1KT26AD001', null).contains('already the USN'),
        'Unique'
      );
      Assert.isTrue(
        refusal(s.first, '1KT26AD009', null).contains('System Administrator'),
        'Staff cannot change a set USN'
      );
    }
    User admin = systemAdministrator();
    System.runAs(admin) {
      Assert.isTrue(refusal(s.first, '1KT26AD009', ' ').contains('reason'));
      CollegeUsnService.setUsn(
        s.first,
        '1KT26AD009',
        'VTU corrected the serial'
      );
    }
    Programme_Enrolment__c e = [
      SELECT USN__c, USN_Set_By__c, USN_Set_On__c
      FROM Programme_Enrolment__c
      WHERE Id = :s.first
    ];
    Assert.areEqual('1KT26AD009', e.USN__c);
    Assert.areEqual(admin.Id, e.USN_Set_By__c);
    Assert.isNotNull(e.USN_Set_On__c);
  }

  @IsTest
  static void aCsvIsCheckedRowByRowAndOnlyValidRowsAreSaved() {
    Setup s = enrolTwo();
    String csv =
      'Enrolment Number,USN\r\n' +
      s.firstNumber +
      ',1KT26AD001\r\n' +
      s.secondNumber +
      ',1KT25AD002\r\n' +
      'NOSUCH001,1KT26AD003\r\n' +
      s.firstNumber +
      ',1KT26AD004\r\n';
    Test.startTest();
    System.runAs(s.fixture.dean) {
      CollegeUsnService.UploadResult check = CollegeSetupController.uploadUsns(
        csv,
        false
      );
      Assert.areEqual(1, check.accepted);
      Assert.areEqual(3, check.rejected);
      Assert.isFalse(check.saved);
      Assert.isTrue(check.rows[1].reason.contains('year'));
      Assert.isTrue(check.rows[2].reason.contains('No student'));
      Assert.isTrue(check.rows[3].reason.contains('twice'));
      Assert.isNull(
        [SELECT USN__c FROM Programme_Enrolment__c WHERE Id = :s.first].USN__c,
        'Checking saves nothing'
      );
      CollegeUsnService.UploadResult saved = CollegeSetupController.uploadUsns(
        csv,
        true
      );
      Assert.isTrue(saved.saved);
    }
    Assert.areEqual(
      '1KT26AD001',
      [SELECT USN__c FROM Programme_Enrolment__c WHERE Id = :s.first].USN__c
    );
    Assert.isNull(
      [SELECT USN__c FROM Programme_Enrolment__c WHERE Id = :s.second].USN__c
    );
  }

  @IsTest
  static void administratorsSetTheVtuCodes() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    User admin = systemAdministrator();
    System.runAs(admin) {
      CollegeSetupController.Setup view = CollegeSetupController.getSetup();
      Assert.isFalse(view.vtuCampuses.isEmpty());
      Assert.isFalse(view.vtuBranches.isEmpty());
      CollegeSetupController.VtuCampus campus = new CollegeSetupController.VtuCampus();
      campus.id = f.campus.Id;
      campus.region = '1';
      campus.college = 'kt';
      CollegeSetupController.saveCampusCodes(campus);
      campus.college = 'K1';
      try {
        CollegeSetupController.saveCampusCodes(campus);
        Assert.fail('Two letters');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('two letters'));
      }
      CollegeSetupController.VtuBranch branch = new CollegeSetupController.VtuBranch();
      branch.id = f.branch.Id;
      branch.vtuCode = 'cs';
      CollegeSetupController.saveBranchCode(branch);
    }
    Assert.areEqual(
      'KT',
      [SELECT VTU_College_Code__c FROM Branch__c WHERE Id = :f.campus.Id]
      .VTU_College_Code__c
    );
    Assert.areEqual(
      'CS',
      [SELECT VTU_Branch_Code__c FROM LearningCourse WHERE Id = :f.branch.Id]
      .VTU_Branch_Code__c
    );
    User teacher = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Teacher', 'KEM_Teacher_Edu' }
    );
    System.runAs(teacher) {
      try {
        CollegeUsnService.upload('A,B', false);
        Assert.fail('College staff only');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('college admission staff'));
      }
    }
  }
}
