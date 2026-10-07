@IsTest
private class PortalAccessTest {
  /** A System Administrator with a role and the KEM Administrator persona. */
  private static User portalAdmin() {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      UserRole role = new UserRole(Name = 'KEM Portal Test ' + key);
      insert role;
      u = new User(
        Alias = ('p' + key).left(8),
        Email = 'kem.pa' + key + '@example.com',
        EmailEncodingKey = 'UTF-8',
        LastName = 'Admin ' + key,
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'en_IN',
        ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator']
        .Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        UserRoleId = role.Id,
        Username = 'kem.pa' + key + '@kasetti.test'
      );
      insert u;
      TestDataFactory.assignEducationLicense(u.Id);
      TestDataFactory.assignPermissionSets(
        u.Id,
        TestDataFactory.persona('KEM_Administrator')
      );
      // The custom permission directly, so the test does not depend on the
      // deployed KEM Administrator set (changes there apply after deployment).
      PermissionSet grant = new PermissionSet(
        Name = 'KEM_Portal_Test_' + key.left(8),
        Label = 'KEM Portal Test ' + key.left(8)
      );
      insert grant;
      insert new SetupEntityAccess(
        ParentId = grant.Id,
        SetupEntityId = [
          SELECT Id
          FROM CustomPermission
          WHERE DeveloperName = :PortalAccessService.MANAGE_PORTAL
        ]
        .Id
      );
      insert new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = grant.Id
      );
    }
    return u;
  }

  private class Family {
    Id guardianId;
    Id learnerId;
    Id teenId;
  }

  private static Family family(Id branchId) {
    FamilySetupService.FamilyRequest r = new FamilySetupService.FamilyRequest();
    r.branchId = branchId;
    FamilySetupService.PersonInput g = new FamilySetupService.PersonInput();
    g.firstName = 'Priya';
    g.lastName = 'Nair';
    g.email =
      'priya.nair.' +
      String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
      '@example.com';
    g.relationship = 'Mother';
    FamilySetupService.PersonInput child = new FamilySetupService.PersonInput();
    child.firstName = 'Diya';
    child.lastName = 'Nair';
    child.birthdate = Date.today().addYears(-9);
    FamilySetupService.PersonInput teen = new FamilySetupService.PersonInput();
    teen.firstName = 'Rohan';
    teen.lastName = 'Nair';
    teen.birthdate = Date.today().addYears(-15);
    r.guardians = new List<FamilySetupService.PersonInput>{ g };
    r.learners = new List<FamilySetupService.PersonInput>{ child, teen };
    FamilySetupService.FamilyResult result = FamilySetupService.createFamily(r);
    Family f = new Family();
    f.guardianId = result.guardianIds[0];
    f.learnerId = result.learnerIds[0];
    f.teenId = result.learnerIds[1];
    return f;
  }

  @IsTest
  static void givesAGuardianAPortalLogin() {
    TestDataFactory.createReferenceData();
    User admin = portalAdmin();
    Family fam;
    System.runAs(admin) {
      fam = family(TestDataFactory.createBranch().Id);
      Assert.isFalse(
        PortalAccessController.prepareAccess(fam.guardianId),
        'Owner already has a role'
      );
    }
    Test.startTest();
    System.runAs(admin) {
      PortalAccessService.Family before = PortalAccessController.getFamily(
        fam.learnerId
      );
      Assert.areEqual(3, before.people.size(), 'Learner, guardian and sibling');
      Assert.isTrue(before.canGive, 'Can give access');
      Map<Id, PortalAccessService.Person> byId = new Map<Id, PortalAccessService.Person>();
      for (PortalAccessService.Person p : before.people) {
        byId.put(p.accountId, p);
      }
      Assert.isTrue(
        byId.get(fam.guardianId).canGive,
        'Guardian ready: ' + byId.get(fam.guardianId).reason
      );
      Assert.isTrue(
        byId.get(fam.learnerId).reason.startsWith('Under 13'),
        'Child: ' + byId.get(fam.learnerId).reason
      );
      Assert.areEqual(
        'Add an email address first',
        byId.get(fam.teenId).reason,
        'Teen has no email'
      );
      Assert.isTrue(before.portalUrl.contains('/s/'), before.portalUrl);

      PortalAccessService.GiveResult given = PortalAccessController.giveAccess(
        fam.guardianId
      );
      Assert.isTrue(given.username.endsWith('.portal'), given.username);
      Assert.isTrue(given.emailSent, 'Welcome email');
    }
    Test.stopTest();
    User u = [
      SELECT ContactId, Profile.Name, IsActive
      FROM User
      WHERE
        Username = :[
          SELECT Username
          FROM User
          WHERE Contact.AccountId = :fam.guardianId
        ]
        .Username
    ];
    Assert.areEqual(
      PortalAccessService.PROFILE_NAME,
      u.Profile.Name,
      'Portal profile'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE AssigneeId = :u.Id AND PermissionSet.Name = 'KEM_Portal_User'
      ],
      'Portal permission set'
    );
    System.runAs(admin) {
      PortalAccessService.Family after = PortalAccessService.family(
        fam.guardianId
      );
      for (PortalAccessService.Person p : after.people) {
        if (p.accountId == fam.guardianId) {
          Assert.isTrue(p.hasLogin, 'Has a login now');
          Assert.isFalse(p.canGive, 'Not twice');
        }
      }
      try {
        PortalAccessService.give(fam.guardianId);
        Assert.fail('Already has a login');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('Has a portal login'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void refusesWithoutLicencesOrPermission() {
    TestDataFactory.createReferenceData();
    User admin = portalAdmin();
    Family fam;
    System.runAs(admin) {
      fam = family(TestDataFactory.createBranch().Id);
      PortalAccessService.freeLicencesOverride = 0;
      try {
        PortalAccessService.give(fam.guardianId);
        Assert.fail('No licences');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('No free portal licences'),
          e.getMessage()
        );
      }
    }
    // A KEM administrator without a role owns the family: prepare moves it to an administrator with a role.
    User roleless = TestDataFactory.admin();
    Id accountId;
    System.runAs(roleless) {
      Account a = PersonAccountService.buildPerson(
        'Meena',
        'Shah',
        'meena.shah@example.com',
        null,
        null,
        'Guardian'
      );
      a.OwnerId = roleless.Id;
      insert a;
      accountId = a.Id;
    }
    System.runAs(admin) {
      Boolean moved;
      try {
        moved = PortalAccessService.prepare(accountId);
      } catch (AppException e) {
        // Only when the org has no administrator with a role.
        Assert.isTrue(
          e.getMessage().contains('needs') ||
          e.getMessage().contains('no administrator'),
          e.getMessage()
        );
        moved = false;
      }
      if (moved) {
        Assert.isNotNull(
          [SELECT Owner.UserRoleId FROM Account WHERE Id = :accountId]
          .Owner.UserRoleId,
          'Owner now has a role'
        );
      }
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      Assert.isFalse(PortalAccessService.canGive(), 'Teachers cannot');
      try {
        PortalAccessController.giveAccess(accountId);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
      try {
        PortalAccessController.prepareAccess(accountId);
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
