@IsTest
private class LearnerServiceTest {
  private static Account createLearner(Id branchId, String lastName) {
    Account learner = PersonAccountService.buildPerson(
      'Ira',
      lastName,
      lastName.toLowerCase() + '@example.com',
      null,
      branchId,
      'Learner'
    );
    insert learner;
    return learner;
  }

  private static LearnerService.GuardianInput guardianInput(String lastName) {
    LearnerService.GuardianInput input = new LearnerService.GuardianInput();
    input.firstName = 'Maya';
    input.lastName = lastName;
    input.email = lastName.toLowerCase() + '.guardian@example.com';
    input.phone = '+919811122233';
    input.relationship = 'Mother';
    input.isFeePayer = true;
    input.portalAccess = true;
    input.isEmergencyContact = true;
    return input;
  }

  @IsTest
  static void learnersGetAProfileWithStudentNumber() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account learner = createLearner(branch.Id, 'Profiled');
      Account guardian = PersonAccountService.buildPerson(
        'G',
        'OnlyGuardian',
        null,
        null,
        branch.Id,
        'Guardian'
      );
      insert guardian;

      Account reloaded = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :learner.Id
      ];
      LearnerProfile profile = [
        SELECT Student_Number__c, Branch__c
        FROM LearnerProfile
        WHERE ContactId = :reloaded.PersonContactId
      ];
      Assert.isTrue(
        profile.Student_Number__c.startsWith('STU-'),
        'Student number generated'
      );
      Assert.areEqual(
        branch.Id,
        profile.Branch__c,
        'Profile carries the home branch'
      );
      Account guardianReloaded = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :guardian.Id
      ];
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM LearnerProfile
          WHERE ContactId = :guardianReloaded.PersonContactId
        ],
        'Guardians get no learner profile'
      );

      update new Account(
        Id = guardian.Id,
        KEM_Role__c = 'Learner and Guardian'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM LearnerProfile
          WHERE ContactId = :guardianReloaded.PersonContactId
        ],
        'Becoming a learner creates a profile'
      );
      update new Account(Id = guardian.Id, KEM_Role__c = 'Learner');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM LearnerProfile
          WHERE ContactId = :guardianReloaded.PersonContactId
        ],
        'Profiles are not duplicated'
      );
    }
  }

  @IsTest
  static void addsGuardiansAndBuildsLearner360() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account learner = createLearner(branch.Id, 'Varma');
      Account sibling = createLearner(branch.Id, 'VarmaJr');

      Id relationId = Learner360Controller.addGuardian(
        learner.Id,
        guardianInput('VarmaParent')
      );
      Assert.isNotNull(relationId, 'Guardian linked');
      Account guardian = [
        SELECT Id, KEM_Role__c
        FROM Account
        WHERE LastName = 'VarmaParent'
      ];
      Assert.areEqual(
        'Guardian',
        guardian.KEM_Role__c,
        'New guardian created with role'
      );

      LearnerService.GuardianInput existing = new LearnerService.GuardianInput();
      existing.existingAccountId = guardian.Id;
      existing.relationship = 'Mother';
      Learner360Controller.addGuardian(sibling.Id, existing);

      // Matching details reuse the same person instead of creating a duplicate.
      Learner360Controller.addGuardian(
        sibling.Id,
        guardianInput('VarmaParent')
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Account WHERE LastName = 'VarmaParent'],
        'No duplicate guardian'
      );

      LearnerService.Learner360 view = Learner360Controller.getLearner360(
        learner.Id
      );
      Assert.isTrue(view.isLearner, 'Learner flag');
      Assert.isNotNull(view.profile, 'Profile returned');
      Assert.areEqual(1, view.guardians.size(), 'One guardian');
      Assert.isTrue(
        view.guardians[0].isFeePayer && view.guardians[0].portalAccess,
        'Guardian flags'
      );
      Assert.areEqual(
        1,
        view.siblings.size(),
        'Sibling found through shared guardian'
      );
      Assert.areEqual(
        sibling.Id,
        view.siblings[0].accountId,
        'Correct sibling'
      );

      LearnerService.Learner360 guardianView = Learner360Controller.getLearner360(
        guardian.Id
      );
      Assert.isTrue(guardianView.isGuardian, 'Guardian flag');
      Assert.areEqual(
        2,
        guardianView.children.size(),
        'Guardian sees both children'
      );
    }
  }

  @IsTest
  static void updatesAndEndsGuardianLinks() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account learner = createLearner(branch.Id, 'Nair');
      Id relationId = LearnerService.addGuardian(
        learner.Id,
        guardianInput('NairParent')
      );

      LearnerService.GuardianInput change = guardianInput('NairParent');
      change.isFeePayer = false;
      change.portalAccess = false;
      change.relationship = 'Guardian';
      Learner360Controller.updateGuardianLink(relationId, change);
      ContactContactRelation rel = [
        SELECT Is_Fee_Payer__c, Portal_Access__c, Guardian_Relationship__c
        FROM ContactContactRelation
        WHERE Id = :relationId
      ];
      Assert.isFalse(
        rel.Is_Fee_Payer__c || rel.Portal_Access__c,
        'Flags cleared'
      );
      Assert.areEqual(
        'Guardian',
        rel.Guardian_Relationship__c,
        'Relationship updated'
      );

      Learner360Controller.endGuardianLink(relationId);
      rel = [
        SELECT IsActive, EndDate
        FROM ContactContactRelation
        WHERE Id = :relationId
      ];
      Assert.isFalse(rel.IsActive, 'Link ended');
      Assert.areEqual(Date.today(), rel.EndDate, 'End date set');
      Assert.areEqual(
        0,
        Learner360Controller.getLearner360(learner.Id).guardians.size(),
        'Ended links are hidden'
      );
    }
  }

  @IsTest
  static void rejectsInvalidGuardianRequests() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account learner = createLearner(branch.Id, 'Self');
      LearnerService.GuardianInput self = new LearnerService.GuardianInput();
      self.existingAccountId = learner.Id;
      try {
        Learner360Controller.addGuardian(learner.Id, self);
        Assert.fail('Self link must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('own guardian'), e.getMessage());
      }
      try {
        Learner360Controller.addGuardian(
          learner.Id,
          new LearnerService.GuardianInput()
        );
        Assert.fail('Missing name must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('last name'), e.getMessage());
      }
      Account business = new Account(Name = 'Acme School Supplies');
      insert business;
      try {
        LearnerService.addGuardian(business.Id, guardianInput('Biz'));
        Assert.fail('Business accounts cannot have guardians');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('person account'),
          e.getMessage()
        );
      }
      LearnerService.Learner360 view = Learner360Controller.getLearner360(
        business.Id
      );
      Assert.isFalse(view.isLearner, 'Business account is not a learner');
      try {
        Learner360Controller.getLearner360(
          TestUtil.fakeId(Account.SObjectType)
        );
        Assert.fail('Unknown record must fail');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Not found');
      }
    }
  }

  @IsTest
  static void updatesPreferencesAndSearchesPeople() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Account learner = createLearner(branch.Id, 'Prefs');
      LearnerService.PreferenceInput input = new LearnerService.PreferenceInput();
      input.preferredChannel = 'WhatsApp';
      input.preferredLanguage = 'Kannada';
      input.whatsAppOptIn = true;
      input.smsOptIn = false;
      input.emailOptOut = true;
      input.emergencyInstructions = 'Peanut allergy';
      Learner360Controller.updatePreferences(learner.Id, input);
      Account saved = [
        SELECT
          Preferred_Channel__pc,
          Preferred_Language__pc,
          WhatsApp_Opt_In__pc,
          PersonHasOptedOutOfEmail,
          Emergency_Instructions__pc
        FROM Account
        WHERE Id = :learner.Id
      ];
      Assert.areEqual('WhatsApp', saved.Preferred_Channel__pc, 'Channel saved');
      Assert.areEqual(
        'Kannada',
        saved.Preferred_Language__pc,
        'Language saved'
      );
      Assert.isTrue(
        saved.WhatsApp_Opt_In__pc && saved.PersonHasOptedOutOfEmail,
        'Consents saved'
      );
      Assert.areEqual(
        'Peanut allergy',
        saved.Emergency_Instructions__pc,
        'Emergency instructions saved'
      );

      Assert.areEqual(
        1,
        Learner360Controller.searchPeople('Prefs').size(),
        'Search by name'
      );
      Assert.areEqual(
        0,
        Learner360Controller.searchPeople('x').size(),
        'Short terms return nothing'
      );
    }
  }

  @IsTest
  static void counsellorManagesGuardians() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      User counsellor = TestDataFactory.createCounsellor(branch.Id);
      System.runAs(counsellor) {
        Account learner = PersonAccountService.buildPerson(
          'Zoya',
          'CounsellorMade',
          'zoya.c@example.com',
          null,
          branch.Id,
          'Learner'
        );
        Database.insert(learner, AccessLevel.USER_MODE);
        Id relationId = Learner360Controller.addGuardian(
          learner.Id,
          guardianInput('CounsellorParent')
        );
        LearnerService.Learner360 view = Learner360Controller.getLearner360(
          learner.Id
        );
        Assert.areEqual(
          1,
          view.guardians.size(),
          'Counsellor sees the guardian'
        );
        Assert.isNotNull(view.profile, 'Counsellor sees the learner profile');
        Assert.isNotNull(relationId, 'Link created by counsellor');
      }
    }
  }

  @IsTest
  static void controllerReportsFailuresAsFriendlyErrors() {
    System.runAs(TestDataFactory.admin()) {
      Id missingRelation = TestUtil.fakeId(ContactContactRelation.SObjectType);
      Id missingAccount = TestUtil.fakeId(Account.SObjectType);
      Integer failures = 0;
      try {
        Learner360Controller.updateGuardianLink(
          missingRelation,
          new LearnerService.GuardianInput()
        );
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        Learner360Controller.endGuardianLink(missingRelation);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        Learner360Controller.updatePreferences(
          missingAccount,
          new LearnerService.PreferenceInput()
        );
      } catch (AuraHandledException e) {
        failures++;
      }
      Assert.areEqual(
        3,
        failures,
        'Each failure surfaces as an AuraHandledException'
      );
    }
  }
}
