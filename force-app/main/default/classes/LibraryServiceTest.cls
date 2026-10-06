@IsTest
private class LibraryServiceTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'LIB-01';
      insert branch;
      insert new List<Library_Item__c>{
        new Library_Item__c(
          Name = 'Wings of Fire',
          Item_Code__c = 'LIB-B-001',
          Item_Type__c = 'Book',
          Author__c = 'A. P. J. Abdul Kalam',
          Branch__c = branch.Id,
          Copies_Total__c = 2,
          Loan_Days__c = 7,
          Daily_Fine__c = 10,
          Replacement_Cost__c = 300
        ),
        new Library_Item__c(
          Name = 'Robotics Kit',
          Item_Code__c = 'LIB-K-001',
          Item_Type__c = 'Kit',
          Branch__c = branch.Id,
          Copies_Total__c = 1
        )
      };
      insert new List<Account>{
        PersonAccountService.buildPerson(
          'Lata',
          'Reader' + Crypto.getRandomInteger(),
          'lata.reader@example.com',
          null,
          branch.Id,
          'Learner'
        ),
        PersonAccountService.buildPerson(
          'Manu',
          'Reader' + Crypto.getRandomInteger(),
          'manu.reader@example.com',
          null,
          branch.Id,
          'Learner'
        )
      };
    }
  }

  private static Branch__c branch() {
    return [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'LIB-01'];
  }
  private static Library_Item__c item(String code) {
    return [
      SELECT
        Id,
        Copies_On_Loan__c,
        Copies_Available__c,
        Copies_Total__c,
        Active__c
      FROM Library_Item__c
      WHERE Item_Code__c = :code
    ];
  }
  private static List<Account> learners() {
    return [
      SELECT Id, PersonContactId, Name
      FROM Account
      WHERE LastName LIKE 'Reader%'
      ORDER BY FirstName
    ];
  }

  @IsTest
  static void issueRenewAndReturnOnTime() {
    System.runAs(TestDataFactory.admin()) {
      Account lata = learners()[0];
      Test.startTest();
      Id loanId = LibraryController.issue(item('LIB-B-001').Id, lata.Id);
      Library_Loan__c loan = [
        SELECT Due_On__c, Status__c, Borrower__c
        FROM Library_Loan__c
        WHERE Id = :loanId
      ];
      Assert.areEqual(
        Date.today().addDays(7),
        loan.Due_On__c,
        'Item loan days'
      );
      Assert.areEqual(lata.PersonContactId, loan.Borrower__c, 'Borrower');
      Assert.areEqual(
        1,
        item('LIB-B-001').Copies_Available__c,
        'One copy left'
      );

      LibraryController.renew(loanId);
      Assert.areEqual(
        Date.today().addDays(14),
        [SELECT Due_On__c FROM Library_Loan__c WHERE Id = :loanId].Due_On__c,
        'Renewed'
      );
      LibraryController.renew(loanId);
      try {
        LibraryController.renew(loanId);
        Assert.fail('Max renewals');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('renewed 2 times'),
          e.getMessage()
        );
      }
      Assert.areEqual(
        0,
        LibraryController.returnLoan(loanId, 'Good'),
        'No fine'
      );
      Test.stopTest();
      Library_Loan__c returned = [
        SELECT Status__c, Fine_Status__c, Return_Condition__c
        FROM Library_Loan__c
        WHERE Id = :loanId
      ];
      Assert.areEqual('Returned', returned.Status__c, 'Returned');
      Assert.areEqual('None', returned.Fine_Status__c, 'No fine');
      Assert.areEqual(2, item('LIB-B-001').Copies_Available__c, 'Copy back');
      try {
        LibraryController.returnLoan(loanId, 'Good');
        Assert.fail('Twice');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('already been returned'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void lateReturnIsFinedAndSettled() {
    System.runAs(TestDataFactory.admin()) {
      Account lata = learners()[0];
      Id loanId = LibraryService.issue(item('LIB-B-001').Id, lata.Id);
      Database.update(
        new Library_Loan__c(Id = loanId, Due_On__c = Date.today().addDays(-3)),
        AccessLevel.SYSTEM_MODE
      );
      try {
        LibraryService.renew(loanId);
        Assert.fail('Overdue cannot be renewed');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('Overdue'), e.getMessage());
      }
      try {
        LibraryService.issue(item('LIB-K-001').Id, lata.Id);
        Assert.fail('Borrower with an overdue loan');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('overdue loan'), e.getMessage());
      }
      Test.startTest();
      Assert.areEqual(
        30,
        LibraryService.returnLoan(loanId, 'Damaged'),
        '3 days x 10'
      );
      LibraryService.Desk desk = LibraryController.getDesk(branch().Id, null);
      Assert.areEqual(1, desk.finesDue.size(), 'Fine listed');
      Assert.areEqual(30, desk.finesOutstanding, 'Outstanding');
      LibraryController.settleFine(loanId, 'Paid');
      Test.stopTest();
      Library_Loan__c loan = [
        SELECT Fine_Status__c, Notes__c, Return_Condition__c
        FROM Library_Loan__c
        WHERE Id = :loanId
      ];
      Assert.areEqual('Paid', loan.Fine_Status__c, 'Paid');
      Assert.areEqual('Damaged', loan.Return_Condition__c, 'Condition');
      Assert.isTrue(loan.Notes__c.contains('Fine paid'), loan.Notes__c);
      try {
        LibraryService.settleFine(loanId, 'Waived');
        Assert.fail('Nothing due');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('no fine due'), e.getMessage());
      }
    }
  }

  @IsTest
  static void lostItemChargesReplacementAndLeavesStock() {
    System.runAs(TestDataFactory.admin()) {
      List<Account> people = learners();
      Id kitLoan = LibraryService.issue(item('LIB-K-001').Id, people[0].Id);
      try {
        LibraryService.issue(item('LIB-K-001').Id, people[1].Id);
        Assert.fail('Only one kit');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('All copies'), e.getMessage());
      }
      Id bookLoan = LibraryService.issue(item('LIB-B-001').Id, people[1].Id);
      Test.startTest();
      Assert.areEqual(
        300,
        LibraryController.markLost(bookLoan),
        'Replacement cost'
      );
      Assert.areEqual(
        0,
        LibraryService.markLost(kitLoan),
        'No replacement cost set'
      );
      Test.stopTest();
      Library_Item__c book = item('LIB-B-001');
      Assert.areEqual(1, book.Copies_Total__c, 'One copy left in stock');
      Assert.areEqual(1, book.Copies_Available__c, 'Available');
      Library_Item__c kit = item('LIB-K-001');
      Assert.isFalse(kit.Active__c, 'Last copy lost: inactive');
      Assert.areEqual(0, kit.Copies_Available__c, 'Nothing to lend');
    }
  }

  @IsTest
  static void overdueJobMarksAndReminds() {
    Id loanId;
    System.runAs(TestDataFactory.admin()) {
      loanId = LibraryService.issue(item('LIB-B-001').Id, learners()[0].Id);
    }
    Database.update(
      new Library_Loan__c(Id = loanId, Due_On__c = Date.today().addDays(-7)),
      AccessLevel.SYSTEM_MODE
    );
    Test.startTest();
    new LibraryJob().execute(null);
    Test.stopTest();
    Assert.areEqual(
      'Overdue',
      [SELECT Status__c FROM Library_Loan__c WHERE Id = :loanId].Status__c,
      'Overdue'
    );
    Message__c reminder = [
      SELECT Subject__c, Body__c
      FROM Message__c
      WHERE Event__c = 'Library_Overdue' AND Channel__c = 'Portal'
    ];
    Assert.isTrue(
      reminder.Subject__c.contains('Wings of Fire'),
      reminder.Subject__c
    );
    Assert.isTrue(
      reminder.Body__c.contains('7 day(s) overdue'),
      reminder.Body__c
    );
    Assert.areEqual(
      0,
      LibraryService.processOverdue(Date.today().addDays(1)),
      'Day 8: no reminder'
    );
    Assert.areEqual(
      1,
      LibraryService.learnerLoans(learners()[0].PersonContactId).size(),
      'Learner loans'
    );
  }

  @IsTest
  static void deskSearchAddItemAndFindLearners() {
    System.runAs(TestDataFactory.admin()) {
      Id branchId = branch().Id;
      LibraryService.Desk desk = LibraryController.getDesk(branchId, 'kalam');
      Assert.areEqual(1, desk.items.size(), 'Search by author');
      Assert.isTrue(desk.canLend && desk.canManageItems, 'Admin can lend');
      Id newItem = LibraryController.addItem(
        new Library_Item__c(
          Name = 'Tablet',
          Item_Code__c = 'lib-d-001',
          Item_Type__c = 'Device',
          Branch__c = branchId,
          Copies_Total__c = 3
        )
      );
      Assert.areEqual(
        'LIB-D-001',
        [SELECT Item_Code__c FROM Library_Item__c WHERE Id = :newItem]
        .Item_Code__c,
        'Code upper-cased'
      );
      Assert.areEqual(
        3,
        LibraryController.getDesk(branchId, null).titles,
        'Three titles'
      );
      Assert.areEqual(
        2,
        LibraryController.findLearners(branchId, 'Reader').size(),
        'Learners found'
      );
      Assert.areEqual(
        0,
        LibraryController.findLearners(branchId, 'R').size(),
        'Too short'
      );
      try {
        LibraryController.addItem(new Library_Item__c(Name = 'No code'));
        Assert.fail('Code required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('item code'), e.getMessage());
      }
      try {
        LibraryController.getDesk(null, null);
        Assert.fail('Branch required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('branch'), e.getMessage());
      }
    }
  }

  @IsTest
  static void teachersCannotLend() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    Id itemId = item('LIB-B-001').Id;
    Id learnerId = learners()[0].Id;
    System.runAs(teacher) {
      try {
        LibraryService.issue(itemId, learnerId);
        Assert.fail('Teachers cannot lend');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
      Assert.isFalse(
        LibraryService.desk(branch().Id, null).canLend,
        'Desk is read-only'
      );
    }
  }
}
