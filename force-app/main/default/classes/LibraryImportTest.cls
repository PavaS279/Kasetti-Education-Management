@IsTest
private class LibraryImportTest {
  private static final String CSV =
    '﻿Title,Code,Type,Author,Subject,Copies,Location,Loan days,Daily fine,Replacement cost\r\n' +
    '"Wings of Fire",kt-bk-001,Book,"Kalam, A P J Abdul",Biography,3,Shelf A,14,5,"₹350"\r\n' +
    'Arduino Starter Kit,KT-KIT-001,Kit,,Robotics,2,Lab cupboard,7,20,2500\r\n' +
    'Existing Abacus,KT-BK-OLD,Book,,Maths,4,,,,\r\n' +
    ',KT-NO-TITLE,Book,,,1,,,,\r\n' +
    'Duplicate,KT-KIT-001,Kit,,,1,,,,\r\n' +
    'Bad copies,KT-BAD,Book,,,lots,,,,\r\n' +
    'Bad type,KT-TYPE,Robot,,,1,,,,\r\n' +
    ',,,,,,,,,\r\n';

  @IsTest
  static void previewsThenImportsTheCatalogue() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Library_Item__c old = new Library_Item__c(
        Name = 'Abacus Workbook',
        Item_Code__c = 'KT-BK-OLD',
        Copies_Total__c = 5,
        Branch__c = branch.Id
      );
      insert old;
      Test.startTest();
      LibraryImportService.Preview p = LibrarySetupController.previewImport(
        branch.Id,
        CSV
      );
      Assert.areEqual(7, p.rows.size(), 'Blank line skipped');
      Assert.areEqual(2, p.newItems, 'New items');
      Assert.areEqual(1, p.addCopies, 'Adds to an existing code');
      Assert.areEqual(4, p.errors, 'Errors');
      Assert.areEqual(9, p.copies, 'Copies');
      Assert.areEqual(
        'Abacus Workbook: 5 → 9 copies',
        p.rows[2].message,
        'Existing item'
      );
      Assert.areEqual('No title', p.rows[3].message, 'Title');
      Assert.areEqual(
        'Code repeated in the file',
        p.rows[4].message,
        'Duplicate'
      );
      Assert.areEqual(
        'Copies and amounts must be numbers',
        p.rows[5].message,
        'Copies'
      );
      Assert.isTrue(p.rows[6].message.startsWith('Type must be'), 'Type');
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Library_Item__c WHERE Item_Code__c = 'KT-BK-001'],
        'Preview saves nothing'
      );

      LibraryImportService.ImportResult r = LibrarySetupController.importItems(
        branch.Id,
        CSV
      );
      Test.stopTest();
      Assert.areEqual(2, r.created, 'Created');
      Assert.areEqual(1, r.updated, 'Updated');
      Assert.areEqual(4, r.skipped, 'Skipped');
      Library_Item__c wings = [
        SELECT
          Author__c,
          Copies_Total__c,
          Replacement_Cost__c,
          Loan_Days__c,
          Item_Type__c,
          Branch__c
        FROM Library_Item__c
        WHERE Item_Code__c = 'KT-BK-001'
      ];
      Assert.areEqual('Kalam, A P J Abdul', wings.Author__c, 'Quoted comma');
      Assert.areEqual(3, wings.Copies_Total__c, 'Copies');
      Assert.areEqual(350, wings.Replacement_Cost__c, 'Rupee amount');
      Assert.areEqual(branch.Id, wings.Branch__c, 'Branch');
      Assert.areEqual(
        9,
        [SELECT Copies_Total__c FROM Library_Item__c WHERE Id = :old.Id]
        .Copies_Total__c,
        'Copies added'
      );

      Assert.areEqual(
        1,
        LibrarySetupController.addCopies(old.Id, 2),
        'Add copies'
      );
      Assert.areEqual(
        11,
        [SELECT Copies_Total__c FROM Library_Item__c WHERE Id = :old.Id]
        .Copies_Total__c,
        'Now 11'
      );
      try {
        LibraryImportService.addCopies(old.Id, 0);
        Assert.fail('At least one');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('between 1'), e.getMessage());
      }
    }
  }

  @IsTest
  static void refusesFilesItCannotRead() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      for (
        String bad : new List<String>{ '', 'Title,Code', 'Name,Author\nX,Y' }
      ) {
        try {
          LibraryImportService.preview(branch.Id, bad);
          Assert.fail('Expected a refusal');
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      try {
        LibraryImportService.preview(null, CSV);
        Assert.fail('Needs a branch');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('branch'), e.getMessage());
      }
      List<List<String>> rows = LibraryImportService.parse(
        'a,"b ""quoted""",c\n"multi\nline",2,3'
      );
      Assert.areEqual('b "quoted"', rows[0][1], 'Doubled quotes');
      Assert.areEqual('multi\nline', rows[1][0], 'Line break inside quotes');
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        LibrarySetupController.previewImport(null, CSV);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        LibrarySetupController.addCopies(null, 1);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        LibrarySetupController.importItems(null, CSV);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
    }
  }
}
