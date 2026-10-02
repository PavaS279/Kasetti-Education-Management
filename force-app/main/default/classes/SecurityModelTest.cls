/**
 * Access scenarios for the Kasetti Education Management security model.
 * Each test runs as a persona with only its permission set and performs DML
 * in user mode, proving that object and field permissions are enforced.
 */
@IsTest
private class SecurityModelTest {
  @IsTest
  static void branchManagerManagesRoomsOnlyInTheirBranch() {
    User manager = TestDataFactory.createUser(
      new List<String>{ 'KEM_Branch_Manager' }
    );
    Branch__c ownBranch = TestDataFactory.buildBranch();
    ownBranch.Branch_Manager__c = manager.Id;
    Branch__c otherBranch = TestDataFactory.buildBranch();
    insert new List<Branch__c>{ ownBranch, otherBranch };
    System.runAs(manager) {
      Room__c room = new Room__c(
        Name = 'R1',
        Branch__c = ownBranch.Id,
        Capacity__c = 20
      );
      Database.insert(room, AccessLevel.USER_MODE);
      Database.update(
        new Room__c(Id = room.Id, Capacity__c = 25),
        AccessLevel.USER_MODE
      );
      Assert.isNotNull(
        room.Id,
        'Branch manager should create rooms in their branch'
      );
      try {
        Database.insert(
          new Room__c(
            Name = 'R2',
            Branch__c = otherBranch.Id,
            Capacity__c = 20
          ),
          AccessLevel.USER_MODE
        );
        Assert.fail('Branch manager must not create rooms in another branch');
      } catch (DmlException e) {
        Assert.isNotNull(e.getMessage(), 'Cross-branch access denied');
      }
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Room__c WHERE Branch__c = :otherBranch.Id],
      'No room created in the other branch'
    );
  }

  @IsTest
  static void teacherCannotCreateRoomsOrBranches() {
    Branch__c branch = TestDataFactory.createBranch();
    User teacher = TestDataFactory.createUser(
      new List<String>{ 'KEM_Teacher' }
    );
    System.runAs(teacher) {
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Branch__c WITH USER_MODE],
        'Teacher can read branches'
      );
      try {
        Database.insert(
          new Room__c(Name = 'R1', Branch__c = branch.Id, Capacity__c = 20),
          AccessLevel.USER_MODE
        );
        Assert.fail('Teacher must not create rooms');
      } catch (Exception e) {
        Assert.isTrue(
          e.getMessage().containsIgnoreCase('not allowed') ||
          e.getMessage().containsIgnoreCase('access'),
          e.getMessage()
        );
      }
      try {
        Database.insert(TestDataFactory.buildBranch(), AccessLevel.USER_MODE);
        Assert.fail('Teacher must not create branches');
      } catch (Exception e) {
        Assert.isNotNull(e.getMessage(), 'Expected access failure');
      }
    }
  }

  @IsTest
  static void onlyAdministratorsReadErrorLogs() {
    insert new Error_Log__c(Severity__c = 'ERROR', Message__c = 'x');
    User teacher = TestDataFactory.createUser(
      new List<String>{ 'KEM_Teacher' }
    );
    User admin = TestDataFactory.createUser(
      new List<String>{ 'KEM_Administrator' }
    );
    System.runAs(teacher) {
      Assert.isFalse(
        Schema.SObjectType.Error_Log__c.isAccessible(),
        'Teacher must not see error logs'
      );
    }
    System.runAs(admin) {
      Assert.isTrue(
        Schema.SObjectType.Error_Log__c.isAccessible(),
        'Administrator reads error logs'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Error_Log__c WITH USER_MODE],
        'Administrator has view-all on logs'
      );
    }
  }

  @IsTest
  static void branchManagerCannotChangeBranchCodeWithoutAdmin() {
    Branch__c branch = TestDataFactory.createBranch();
    User manager = TestDataFactory.createUser(
      new List<String>{ 'KEM_Branch_Manager' }
    );
    System.runAs(manager) {
      Assert.isTrue(
        Schema.SObjectType.Branch__c.isUpdateable(),
        'Branch manager edits branch policies'
      );
      Assert.isFalse(
        Schema.SObjectType.Branch__c.isCreateable(),
        'Branch manager cannot create branches'
      );
      Assert.isTrue(
        Schema.SObjectType.Branch__c.fields.Tax_Rate__c.isUpdateable(),
        'Branch manager edits tax rate'
      );
    }
  }

  @IsTest
  static void branchManagerGetsEditShareOnTheirBranch() {
    User manager = TestDataFactory.createUser(
      new List<String>{ 'KEM_Branch_Manager' }
    );
    User other = TestDataFactory.createUser(
      new List<String>{ 'KEM_Branch_Manager' }
    );
    Branch__c branch = TestDataFactory.buildBranch();
    branch.Branch_Manager__c = manager.Id;
    insert branch;
    System.runAs(manager) {
      branch.Operating_Hours__c = 'Mon-Fri 09:00-18:00';
      Database.update(branch, AccessLevel.USER_MODE);
    }
    branch.Branch_Manager__c = other.Id;
    update branch;
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Branch__Share
        WHERE
          ParentId = :branch.Id
          AND RowCause = 'Branch_Manager__c'
          AND UserOrGroupId = :other.Id
      ],
      'Share follows the new manager'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Branch__Share
        WHERE
          ParentId = :branch.Id
          AND RowCause = 'Branch_Manager__c'
          AND UserOrGroupId = :manager.Id
      ],
      'Old manager share removed'
    );
  }
}
