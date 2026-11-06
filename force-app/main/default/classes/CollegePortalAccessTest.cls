@IsTest
private class CollegePortalAccessTest {
  private class Setup {
    CollegeTestFactory.Fixture fixture;
    User desk;
    String email;
  }

  /** A college admission whose student has an email and an owner with a role. */
  private static Setup prepare() {
    Setup s = new Setup();
    s.fixture = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    s.email = 'college.student.' + key + '@example.com';
    User owner;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      UserRole role = new UserRole(Name = 'KEM College Portal ' + key);
      insert role;
      owner = new User(
        Alias = ('c' + key).left(8),
        Email = 'kem.cp' + key + '@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'Owner ' + key,
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_IN',
        ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator']
        .Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        UserRoleId = role.Id,
        Username = 'kem.cp' + key + '@kasetti.test'
      );
      insert owner;
    }
    update new Account(
      Id = s.fixture.admission.AccountId,
      PersonEmail = s.email,
      OwnerId = owner.Id
    );
    s.desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    // In the org the admissions-team sharing rule gives edit access.
    insert new IndividualApplicationShare(
      ParentId = s.fixture.admission.Id,
      UserOrGroupId = s.desk.Id,
      AccessLevel = 'Edit',
      RowCause = 'Manual'
    );
    return s;
  }

  private static Integer logins(Id accountId) {
    return [
      SELECT COUNT()
      FROM User
      WHERE Contact.AccountId = :accountId AND IsActive = TRUE
    ];
  }

  @IsTest
  static void counsellorGivesAccessFromTheAdmission() {
    Setup s = prepare();
    Id applicationId = s.fixture.admission.Id;
    System.runAs(s.fixture.dean) {
      InterviewService.admit(applicationId);
    }
    Test.startTest();
    System.runAs(s.desk) {
      CollegeAdmissionController.Admission view = CollegeAdmissionController.getAdmission(
        applicationId
      );
      Assert.areEqual('Not given', view.portal.label);
      Assert.isTrue(view.portal.canGive);
    }
    System.runAs(s.desk) {
      CollegeAdmissionController.givePortal(applicationId);
    }
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(1, logins(s.fixture.admission.AccountId));
    System.runAs(s.desk) {
      CollegeAdmissionController.Admission view = CollegeAdmissionController.getAdmission(
        applicationId
      );
      Assert.areEqual('Active', view.portal.label);
      Assert.isTrue(view.portal.canResend);
      Assert.areEqual(
        s.email,
        CollegeAdmissionController.sendPortalLink(applicationId)
      );
    }
  }

  @IsTest
  static void admittingGivesAccessAutomatically() {
    Setup s = prepare();
    CollegePortalAccessService.autoInTests = true;
    Test.startTest();
    System.runAs(s.fixture.dean) {
      InterviewService.admit(s.fixture.admission.Id);
    }
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(1, logins(s.fixture.admission.AccountId));
  }

  @IsTest
  static void noAccessBeforeAdmissionOrWithoutTheDeskPermission() {
    Setup s = prepare();
    System.runAs(s.desk) {
      CollegeAdmissionController.Admission view = CollegeAdmissionController.getAdmission(
        s.fixture.admission.Id
      );
      Assert.isNull(view.portal, 'Not admitted yet');
      try {
        CollegePortalAccessService.request(s.fixture.admission.Id);
        Assert.fail('Only admitted students');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('admitted'), e.getMessage());
      }
    }
    User teacher = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Teacher', 'KEM_Teacher_Edu' }
    );
    System.runAs(teacher) {
      try {
        CollegePortalAccessService.request(s.fixture.admission.Id);
        Assert.fail('Only the admission desk');
      } catch (Exception e) {
        Assert.isTrue(true);
      }
    }
  }
}
