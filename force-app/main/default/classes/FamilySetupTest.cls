@IsTest
private class FamilySetupTest {
  private static FamilySetupService.PersonInput guardian(
    String first,
    String last,
    String email,
    String rel
  ) {
    FamilySetupService.PersonInput p = new FamilySetupService.PersonInput();
    p.firstName = first;
    p.lastName = last;
    p.email = email;
    p.phone =
      '+91 98450 ' +
      String.valueOf(Crypto.getRandomInteger()).right(5).replace('-', '1');
    p.relationship = rel;
    p.preferredLanguage = 'Kannada';
    p.preferredChannel = 'WhatsApp';
    return p;
  }

  private static FamilySetupService.PersonInput learner(
    String first,
    String last,
    Integer age
  ) {
    FamilySetupService.PersonInput p = new FamilySetupService.PersonInput();
    p.firstName = first;
    p.lastName = last;
    p.birthdate = Date.today().addYears(-age);
    p.school = 'National Public School';
    p.nextStep = 'none';
    return p;
  }

  private class Fixture {
    Branch__c branch;
    LearningCourse course;
    CourseOffering offering;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    f.course = TestDataFactory.createCourse('Python for Kids');
    insert new Fee_Price__c(
      Learning_Course__c = f.course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Monthly',
      Amount__c = 2500,
      Effective_From__c = Date.today().addDays(-10),
      Active__c = true
    );
    f.offering = TestDataFactory.createOffering(f.course.Id, f.branch.Id, 10);
    return f;
  }

  @IsTest
  static void createsAWalkInFamilyWithEnrolmentAndApplication() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      FamilySetupService.FamilyRequest r = new FamilySetupService.FamilyRequest();
      r.branchId = f.branch.Id;
      r.city = 'Bengaluru';
      FamilySetupService.PersonInput mother = guardian(
        'Kavya',
        'Rao',
        'kavya.rao@example.com',
        'Mother'
      );
      FamilySetupService.PersonInput father = guardian(
        'Suresh',
        'Rao',
        null,
        'Father'
      );
      father.isFeePayer = true;
      FamilySetupService.PersonInput older = learner('Aditi', 'Rao', 11);
      older.nextStep = 'enrol';
      older.offeringId = f.offering.Id;
      FamilySetupService.PersonInput younger = learner('Arjun', 'Rao', 8);
      younger.nextStep = 'apply';
      younger.courseId = f.course.Id;
      r.guardians = new List<FamilySetupService.PersonInput>{
        mother,
        father,
        guardian('', '', null, null)
      };
      r.learners = new List<FamilySetupService.PersonInput>{ older, younger };

      FamilySetupService.Choices choices = FamilySetupController.getChoices(
        f.branch.Id
      );
      Assert.areEqual(1, choices.classes.size(), 'Open class offered');
      Assert.isTrue(
        choices.classes[0].label.contains('10 seats free'),
        choices.classes[0].label
      );
      Assert.isTrue(
        FamilySetupController.findMatches(r).isEmpty(),
        'Nobody exists yet'
      );

      Test.startTest();
      FamilySetupService.FamilyResult result = FamilySetupController.createFamily(
        r
      );
      Test.stopTest();

      Assert.areEqual(
        2,
        result.guardianIds.size(),
        'Blank guardian line skipped'
      );
      Assert.areEqual(2, result.learnerIds.size(), 'Learners');
      Assert.areEqual(4, result.created, 'Four people');
      Assert.areEqual(1, result.enrolmentIds.size(), 'Aditi enrolled');
      Assert.areEqual(1, result.applicationIds.size(), 'Arjun applied');
      Account aditi = [
        SELECT
          KEM_Role__c,
          PersonBirthdate,
          Description,
          Branch__c,
          PersonMailingCity,
          PersonContactId
        FROM Account
        WHERE Id = :result.learnerIds[0]
      ];
      Assert.areEqual('Learner', aditi.KEM_Role__c, 'Role');
      Assert.areEqual(
        'School: National Public School',
        aditi.Description,
        'School'
      );
      Assert.areEqual('Bengaluru', aditi.PersonMailingCity, 'Address');
      Account kavya = [
        SELECT Preferred_Language__pc, KEM_Role__c
        FROM Account
        WHERE Id = :result.guardianIds[0]
      ];
      Assert.areEqual('Kannada', kavya.Preferred_Language__pc, 'Language');
      Map<String, Boolean> payer = new Map<String, Boolean>();
      for (ContactContactRelation l : [
        SELECT Guardian_Relationship__c, Is_Fee_Payer__c
        FROM ContactContactRelation
        WHERE RelatedContactId = :aditi.PersonContactId
      ]) {
        payer.put(l.Guardian_Relationship__c, l.Is_Fee_Payer__c);
      }
      Assert.areEqual(2, payer.size(), 'Both guardians linked');
      Assert.isTrue(payer.get('Father'), 'Father chosen as fee payer');
      Assert.isFalse(payer.get('Mother'), 'Mother not paying');
      Assert.areEqual(
        4,
        [
          SELECT COUNT()
          FROM ContactContactRelation
          WHERE
            ContactId IN (
              SELECT PersonContactId
              FROM Account
              WHERE Id IN :result.guardianIds
            )
        ],
        'Every guardian to every learner'
      );
      IndividualApplication app = [
        SELECT Status, Branch__c, Learning_Course__c, Eligibility_Status__c
        FROM IndividualApplication
        WHERE Id = :result.applicationIds[0]
      ];
      Assert.areEqual('Processing', app.Status, 'New application');
      Assert.areEqual(f.branch.Id, app.Branch__c, 'Branch');

      // A second open application for the same course is refused.
      try {
        FamilySetupService.newApplication(
          result.learnerIds[1],
          null,
          f.course.Id,
          null
        );
        Assert.fail('Duplicate application');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already has an open application'),
          e.getMessage()
        );
      }
      try {
        FamilySetupService.newApplication(
          result.guardianIds[0],
          null,
          f.course.Id,
          null
        );
        Assert.fail('Guardians do not apply');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('not a learner'), e.getMessage());
      }
      Id another = FamilySetupController.createApplication(
        result.learnerIds[0],
        null,
        TestDataFactory.createCourse('Robotics Club').Id,
        null
      );
      Assert.isNotNull(another, 'Application for an existing learner');
    }
  }

  @IsTest
  static void findsExistingPeopleAndReusesThem() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Account existing = PersonAccountService.buildPerson(
        'Kavya',
        'Rao',
        'kavya.rao@example.com',
        null,
        f.branch.Id,
        'Learner'
      );
      insert existing;
      FamilySetupService.FamilyRequest r = new FamilySetupService.FamilyRequest();
      r.branchId = f.branch.Id;
      r.guardians = new List<FamilySetupService.PersonInput>{
        guardian('Kavya', 'Rao', 'Kavya.Rao@example.com', 'Mother')
      };
      FamilySetupService.PersonInput twin = learner('Isha', 'Menon', 9);
      Account sameLearner = PersonAccountService.buildPerson(
        'Isha',
        'Menon',
        null,
        null,
        f.branch.Id,
        'Learner'
      );
      sameLearner.PersonBirthdate = twin.birthdate;
      insert sameLearner;
      r.learners = new List<FamilySetupService.PersonInput>{ twin };

      List<FamilySetupService.Match> matches = FamilySetupService.findMatches(
        r
      );
      Assert.areEqual(
        2,
        matches.size(),
        'Guardian by email, learner by name and birthday'
      );
      Assert.areEqual(existing.Id, matches[0].accountId, 'Guardian match');
      Assert.areEqual(sameLearner.Id, matches[1].accountId, 'Learner match');

      r.guardians[0].existingAccountId = existing.Id;
      r.learners[0].existingAccountId = sameLearner.Id;
      FamilySetupService.FamilyResult result = FamilySetupService.createFamily(
        r
      );
      Assert.areEqual(2, result.reused, 'Both reused');
      Assert.areEqual(0, result.created, 'No duplicates');
      Assert.areEqual(
        'Learner and Guardian',
        [SELECT KEM_Role__c FROM Account WHERE Id = :existing.Id].KEM_Role__c,
        'Role merged'
      );
    }
  }

  @IsTest
  static void refusesIncompleteFamiliesWithNothingSaved() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Integer people = [SELECT COUNT() FROM Account];
      FamilySetupService.FamilyRequest noLearner = new FamilySetupService.FamilyRequest();
      noLearner.branchId = f.branch.Id;
      noLearner.guardians = new List<FamilySetupService.PersonInput>{
        guardian('A', 'B', 'a@example.com', 'Mother')
      };
      FamilySetupService.FamilyRequest noContact = new FamilySetupService.FamilyRequest();
      noContact.branchId = f.branch.Id;
      FamilySetupService.PersonInput silent = guardian(
        'A',
        'B',
        null,
        'Mother'
      );
      silent.phone = null;
      noContact.guardians = new List<FamilySetupService.PersonInput>{ silent };
      noContact.learners = new List<FamilySetupService.PersonInput>{
        learner('C', 'B', 9)
      };
      FamilySetupService.FamilyRequest noBirthday = new FamilySetupService.FamilyRequest();
      noBirthday.branchId = f.branch.Id;
      FamilySetupService.PersonInput unborn = learner('C', 'B', 9);
      unborn.birthdate = null;
      noBirthday.learners = new List<FamilySetupService.PersonInput>{ unborn };
      FamilySetupService.FamilyRequest noClass = new FamilySetupService.FamilyRequest();
      noClass.branchId = f.branch.Id;
      FamilySetupService.PersonInput classless = learner('C', 'B', 9);
      classless.nextStep = 'enrol';
      noClass.learners = new List<FamilySetupService.PersonInput>{ classless };
      FamilySetupService.FamilyRequest noBranch = new FamilySetupService.FamilyRequest();
      noBranch.learners = new List<FamilySetupService.PersonInput>{
        learner('C', 'B', 9)
      };
      for (
        FamilySetupService.FamilyRequest bad : new List<FamilySetupService.FamilyRequest>{
          noLearner,
          noContact,
          noBirthday,
          noClass,
          noBranch
        }
      ) {
        try {
          FamilySetupService.createFamily(bad);
          Assert.fail('Expected a refusal');
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      // A full class fails the enrolment: the family is rolled back.
      update new CourseOffering(
        Id = f.offering.Id,
        Class_Status__c = 'Planned'
      );
      FamilySetupService.FamilyRequest closed = new FamilySetupService.FamilyRequest();
      closed.branchId = f.branch.Id;
      FamilySetupService.PersonInput late = learner('Late', 'Comer', 10);
      late.nextStep = 'enrol';
      late.offeringId = f.offering.Id;
      closed.learners = new List<FamilySetupService.PersonInput>{ late };
      try {
        FamilySetupController.createFamily(closed);
        Assert.fail('Class not open');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Explained');
      }
      Assert.areEqual(
        people,
        [SELECT COUNT() FROM Account],
        'Nothing half-saved'
      );
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        FamilySetupController.findMatches(
          new FamilySetupService.FamilyRequest()
        );
        Assert.fail('Teachers do not add families');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
    }
  }
}
