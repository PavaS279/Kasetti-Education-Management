@IsTest
private class AdmissionRuleServiceTest {
  @IsTest
  static void activatesAndSupersedesVersions() {
    User admin = TestDataFactory.admin();
    LearningCourse branch = TestDataFactory.createCourse('Rule Branch');
    Admission_Rule__c first = rule(branch.Id);
    System.runAs(admin) {
      insert first;
      AdmissionRuleService.activate(first.Id);
    }
    first = [SELECT Version__c FROM Admission_Rule__c WHERE Id = :first.Id];
    System.assertEquals(1, first.Version__c);
    Admission_Rule__c second = rule(branch.Id);
    System.runAs(admin) {
      insert second;
      AdmissionRuleService.activate(second.Id);
    }
    second = [SELECT Version__c FROM Admission_Rule__c WHERE Id = :second.Id];
    System.assertEquals(2, second.Version__c);
    Map<Id, Admission_Rule__c> results = new Map<Id, Admission_Rule__c>(
      [
        SELECT Status__c, Active_Key__c, Effective_To__c
        FROM Admission_Rule__c
        WHERE Id IN :new Set<Id>{ first.Id, second.Id }
      ]
    );
    System.assertEquals('Superseded', results.get(first.Id).Status__c);
    System.assertNotEquals(null, results.get(first.Id).Effective_To__c);
    System.assertEquals('Active', results.get(second.Id).Status__c);
    System.assertNotEquals(null, results.get(second.Id).Active_Key__c);
  }
  @IsTest
  static void requiresEntranceAndLocksActiveRule() {
    User admin = TestDataFactory.admin();
    LearningCourse branch = TestDataFactory.createCourse(
      'Entrance Rule Branch'
    );
    Admission_Rule__c value = rule(branch.Id);
    value.Entrance_Required__c = true;
    System.runAs(admin) {
      insert value;
      try {
        AdmissionRuleService.activate(value.Id);
        System.assert(false);
      } catch (AppException e) {
        System.assert(e.getMessage().contains('entrance'));
      }
    }
    System.runAs(admin) {
      insert new Admission_Rule_Entrance__c(
        Admission_Rule__c = value.Id,
        Entrance_Exam__c = 'KCET',
        Max_Rank__c = 20000
      );
      AdmissionRuleService.activate(value.Id);
    }
    Database.SaveResult changed = Database.update(
      new Admission_Rule__c(Id = value.Id, Min_Percentage__c = 80),
      false
    );
    System.assertEquals(false, changed.isSuccess());
    Admission_Rule_Entrance__c acceptedEntrance = [
      SELECT Id
      FROM Admission_Rule_Entrance__c
      WHERE Admission_Rule__c = :value.Id
      LIMIT 1
    ];
    Database.DeleteResult removed = Database.delete(acceptedEntrance, false);
    System.assertEquals(false, removed.isSuccess());
  }
  @IsTest
  static void assignsSequentialVersionsInBulk() {
    User admin = TestDataFactory.admin();
    LearningCourse branch = TestDataFactory.createCourse('Bulk Rule Branch');
    Admission_Rule__c first = rule(branch.Id);
    Admission_Rule__c second = rule(branch.Id);
    System.runAs(admin) {
      insert new List<Admission_Rule__c>{ first, second };
    }
    List<Admission_Rule__c> versions = [
      SELECT Version__c, Version_Key__c
      FROM Admission_Rule__c
      WHERE Id IN :new Set<Id>{ first.Id, second.Id }
      ORDER BY Version__c
    ];
    System.assertEquals(1, versions[0].Version__c);
    System.assertEquals(2, versions[1].Version__c);
    System.assertNotEquals(
      versions[0].Version_Key__c,
      versions[1].Version_Key__c
    );
  }

  @IsTest
  static void clonesEntrancesAndRetiresActiveRule() {
    User admin = TestDataFactory.admin();
    LearningCourse branch = TestDataFactory.createCourse('Clone Rule Branch');
    Id sourceId;
    Id cloneId;
    System.runAs(admin) {
      Admission_Rule__c source = rule(branch.Id);
      source.Entrance_Required__c = true;
      insert source;
      insert new Admission_Rule_Entrance__c(
        Admission_Rule__c = source.Id,
        Entrance_Exam__c = 'KCET',
        Max_Rank__c = 20000
      );
      AdmissionRuleService.activate(source.Id);
      sourceId = source.Id;
      cloneId = AdmissionRuleService.cloneAsDraft(source.Id);
    }
    Admission_Rule__c copied = [
      SELECT Status__c, Version__c, Effective_From__c, Active_Key__c
      FROM Admission_Rule__c
      WHERE Id = :cloneId
    ];
    System.assertEquals('Draft', copied.Status__c);
    System.assertEquals(2, copied.Version__c);
    System.assertEquals(null, copied.Effective_From__c);
    System.assertEquals(null, copied.Active_Key__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Admission_Rule_Entrance__c
        WHERE Admission_Rule__c = :cloneId
      ]
    );
    System.runAs(admin) {
      AdmissionRuleService.retire(sourceId);
    }
    Admission_Rule__c retired = [
      SELECT Status__c, Effective_To__c, Active_Key__c
      FROM Admission_Rule__c
      WHERE Id = :sourceId
    ];
    System.assertEquals('Retired', retired.Status__c);
    System.assertNotEquals(null, retired.Effective_To__c);
    System.assertEquals(null, retired.Active_Key__c);
  }

  @IsTest
  static void rejectsInvalidAcademicYear() {
    LearningCourse branch = TestDataFactory.createCourse('Year Rule Branch');
    Admission_Rule__c invalid = rule(branch.Id);
    invalid.Academic_Year__c = '2026-28';
    Database.SaveResult result = Database.insert(invalid, false);
    System.assertEquals(false, result.isSuccess());
    System.assert(result.getErrors()[0].getMessage().contains('YYYY-YY'));
  }

  private static Admission_Rule__c rule(Id branchId) {
    return new Admission_Rule__c(
      Branch__c = branchId,
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Status__c = 'Draft',
      Entry_Year_Of_Study__c = 1,
      Qualifying_Level__c = 'PUC',
      Min_Percentage__c = 75
    );
  }
}
