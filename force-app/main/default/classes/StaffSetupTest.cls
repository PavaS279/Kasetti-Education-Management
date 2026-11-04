@IsTest
private class StaffSetupTest {
  private static StaffSetupService.StaffRequest request(String email) {
    StaffSetupService.StaffRequest r = new StaffSetupService.StaffRequest();
    r.firstName = 'Meera';
    r.lastName = 'Pillai';
    r.email = email;
    r.mobile = '+91 98450 12345';
    r.persona = 'KEM_Teacher_Persona';
    r.aiUser = true;
    r.sendEmail = false;
    return r;
  }

  /** A System Administrator (Manage Users) holding the KEM Administrator persona. */
  private static User staffAdmin() {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      u = new User(
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
      insert u;
      TestDataFactory.assignEducationLicense(u.Id);
      TestDataFactory.assignPermissionSets(
        u.Id,
        TestDataFactory.persona('KEM_Administrator')
      );
    }
    return u;
  }

  private static void calculateGroups() {
    for (PermissionSetGroup g : [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName IN :StaffSetupService.PERSONAS.keySet()
    ]) {
      Test.calculatePermissionSetGroup(g.Id);
    }
  }

  @IsTest
  static void createsALoginThenItsBranchRoles() {
    User admin = staffAdmin();
    Branch__c branch;
    System.runAs(admin) {
      branch = TestDataFactory.createBranch();
    }
    calculateGroups();
    Id userId;
    String email =
      'meera.' +
      TestDataFactory.unique('t').replace('-', '') +
      '@example.com';
    Test.startTest();
    System.runAs(admin) {
      userId = StaffSetupController.createLogin(request(email));
    }
    System.runAs(admin) {
      StaffSetupService.RoleLine teach = new StaffSetupService.RoleLine();
      teach.branchId = branch.Id;
      teach.role = 'Teacher';
      StaffSetupService.RoleLine twice = new StaffSetupService.RoleLine();
      twice.branchId = branch.Id;
      twice.role = 'Teacher';
      Assert.areEqual(
        1,
        StaffSetupController.assignRoles(
          userId,
          new List<StaffSetupService.RoleLine>{ teach, twice }
        ),
        'One role'
      );
      Assert.areEqual(
        0,
        StaffSetupService.assignRoles(
          userId,
          new List<StaffSetupService.RoleLine>{ teach }
        ),
        'Already held'
      );
    }
    Test.stopTest();

    User u = [
      SELECT
        Username,
        Profile.Name,
        LocaleSidKey,
        TimeZoneSidKey,
        Title,
        IsActive
      FROM User
      WHERE Id = :userId
    ];
    Assert.areEqual(
      email + StaffSetupService.usernameSuffix(),
      u.Username,
      'Username'
    );
    Assert.areEqual(
      StaffSetupService.PROFILE_NAME,
      u.Profile.Name,
      'Staff profile'
    );
    Assert.areEqual('en_IN', u.LocaleSidKey, 'Indian locale');
    Assert.areEqual('Teacher', u.Title, 'Title from persona');
    Set<String> granted = new Set<String>();
    for (PermissionSetAssignment a : [
      SELECT PermissionSet.Name, PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
    ]) {
      granted.add(a.PermissionSetGroup?.DeveloperName ?? a.PermissionSet.Name);
    }
    Assert.isTrue(
      granted.contains('KEM_Teacher_Persona'),
      String.valueOf(granted)
    );
    Assert.isTrue(granted.contains('KEM_AI_User'), String.valueOf(granted));
    Assert.isTrue(
      granted.contains('EducationCloudAccess'),
      String.valueOf(granted)
    );
    Branch_Staff__c role = [
      SELECT Id, Role__c
      FROM Branch_Staff__c
      WHERE User__c = :userId
    ];
    Assert.areEqual('Teacher', role.Role__c, 'Branch role');

    System.runAs(admin) {
      StaffSetupService.Overview o = StaffSetupController.getOverview();
      Assert.areEqual(6, o.personas.size(), 'Personas');
      Assert.isTrue(o.roles.contains('Teacher'), 'Roles');
      Boolean listed = false;
      for (StaffSetupService.StaffRow s : o.staff) {
        if (s.userId == userId) {
          listed = s.roles.size() == 1 && s.persona == 'Teacher';
        }
      }
      Assert.isTrue(listed, 'New staff member listed with role');
      StaffSetupController.endRole(role.Id);
      // Ending then re-adding the role re-activates it.
      StaffSetupService.RoleLine again = new StaffSetupService.RoleLine();
      again.branchId = branch.Id;
      again.role = 'Teacher';
      Assert.areEqual(
        1,
        StaffSetupService.assignRoles(
          userId,
          new List<StaffSetupService.RoleLine>{ again }
        ),
        'Re-activated'
      );
    }
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Branch_Staff__c WHERE User__c = :userId],
      'No duplicate row'
    );
  }

  @IsTest
  static void refusesBadRequestsAndFullLicences() {
    User admin = staffAdmin();
    System.runAs(admin) {
      String email =
        'dup.' +
        TestDataFactory.unique('t').replace('-', '') +
        '@example.com';
      StaffSetupService.StaffRequest noPersona = request(email);
      noPersona.persona = 'KEM_Integration_Persona';
      StaffSetupService.StaffRequest badEmail = request('not-an-email');
      StaffSetupService.StaffRequest noName = request(email);
      noName.lastName = ' ';
      StaffSetupService.StaffRequest takenEmail = request(admin.Email);
      takenEmail.username = 'other.' + email;
      for (
        StaffSetupService.StaffRequest bad : new List<StaffSetupService.StaffRequest>{
          noPersona,
          badEmail,
          noName,
          takenEmail
        }
      ) {
        try {
          StaffSetupService.createLogin(bad);
          Assert.fail('Expected a refusal');
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      StaffSetupService.freeLicencesOverride = 0;
      try {
        StaffSetupController.createLogin(request(email));
        Assert.fail('No licences');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('no free'), e.getMessage());
      }
    }
  }

  @IsTest
  static void onlyStaffManagersMayUseIt() {
    // KEM Administrators without Manage Users cannot add logins either.
    System.runAs(TestDataFactory.admin()) {
      Assert.isFalse(StaffSetupService.canManage(), 'Needs Manage Users too');
    }
    User manager = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Branch_Manager')
    );
    System.runAs(manager) {
      Assert.isFalse(
        StaffSetupService.canManage(),
        'Branch managers do not add logins'
      );
      try {
        StaffSetupController.getOverview();
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
      try {
        StaffSetupController.assignRoles(null, null);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
      try {
        StaffSetupController.endRole(null);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
    }
  }
}
