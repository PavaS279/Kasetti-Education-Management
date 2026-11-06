@IsTest
private class CollegeFeeSetupTest {
  private static CollegeFeeSetupService.Cell cell(Id quotaId, Decimal amount) {
    CollegeFeeSetupService.Cell c = new CollegeFeeSetupService.Cell();
    c.quotaId = quotaId;
    c.amount = amount;
    return c;
  }

  @IsTest
  static void aQuotaPriceIsChargedAtAdmit() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Admission_Quota__c management = new Admission_Quota__c(
      Name = 'Management',
      Code__c = 'MGMT'
    );
    insert management;
    insert new Seat_Quota__c(
      Campus_Branch__c = f.intake.Id,
      Admission_Quota__c = management.Id,
      Seats__c = 5
    );
    // The factory's default tuition is 1,00,000; Management pays 2,50,000.
    CollegeFeeSetupService.FeeSave request = new CollegeFeeSetupService.FeeSave();
    request.courseId = f.branch.Id;
    request.academicYear = '2026-27';
    request.effectiveFrom = Date.today();
    CollegeFeeSetupService.FeeRow tuition = new CollegeFeeSetupService.FeeRow();
    tuition.feeType = 'Tuition';
    tuition.frequency = 'Annual';
    tuition.cells = new List<CollegeFeeSetupService.Cell>{
      cell(null, 100000),
      cell(management.Id, 250000)
    };
    request.rows = new List<CollegeFeeSetupService.FeeRow>{ tuition };
    CollegeFeeSetupService.save(request);

    CollegeFeeSetupService.FeeGrid grid = CollegeFeeSetupService.grid(
      f.branch.Id,
      '2026-27',
      null
    );
    Assert.areEqual(2, grid.quotas.size(), 'Default column and Management');
    for (CollegeFeeSetupService.FeeRow row : grid.rows) {
      if (row.feeType == 'Tuition') {
        Assert.areEqual(100000, row.cells[0].amount);
        Assert.areEqual(250000, row.cells[1].amount);
      }
    }

    update new IndividualApplication(
      Id = f.admission.Id,
      Admission_Quota__c = management.Id
    );
    Test.startTest();
    Id enrolmentId;
    System.runAs(f.dean) {
      enrolmentId = InterviewService.admit(f.admission.Id);
    }
    Test.stopTest();
    // The line carries the price; the invoice total adds the campus tax.
    Assert.areEqual(
      250000,
      [
        SELECT Unit_Amount__c
        FROM Invoice_Line__c
        WHERE
          Student_Invoice__c = :CollegeTestFactory.invoiceOf(enrolmentId).Id
          AND Fee_Type__c = 'Tuition'
      ]
      .Unit_Amount__c,
      'The Management tuition is charged'
    );
  }

  @IsTest
  static void aChangeEndsTheOldPriceAndStartsANewOne() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    Fee_Price__c original = [
      SELECT Id
      FROM Fee_Price__c
      WHERE Learning_Course__c = :f.branch.Id
    ];
    CollegeFeeSetupService.FeeSave request = new CollegeFeeSetupService.FeeSave();
    request.courseId = f.branch.Id;
    request.academicYear = '2026-27';
    request.effectiveFrom = Date.today().addDays(30);
    CollegeFeeSetupService.FeeRow tuition = new CollegeFeeSetupService.FeeRow();
    tuition.feeType = 'Tuition';
    tuition.frequency = 'Annual';
    tuition.cells = new List<CollegeFeeSetupService.Cell>{ cell(null, 120000) };
    request.rows = new List<CollegeFeeSetupService.FeeRow>{ tuition };
    CollegeFeeSetupService.save(request);
    Assert.areEqual(
      Date.today().addDays(29),
      [SELECT Effective_To__c FROM Fee_Price__c WHERE Id = :original.Id]
      .Effective_To__c,
      'The old price runs until the day before'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Fee_Price__c
        WHERE
          Learning_Course__c = :f.branch.Id
          AND Amount__c = 120000
          AND Effective_From__c = :Date.today().addDays(30)
      ]
    );
    request.effectiveFrom = Date.today().addDays(-1);
    try {
      CollegeFeeSetupService.save(request);
      Assert.fail('No back-dated fees');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('today or later'));
    }
    tuition.cells[0].amount = -5;
    request.effectiveFrom = Date.today();
    try {
      CollegeFeeSetupService.save(request);
      Assert.fail('No negative fees');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('0 or more'));
    }
  }

  @IsTest
  static void onlyASystemAdministratorSavesFees() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    User desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    System.runAs(desk) {
      Assert.isFalse(
        CollegeSetupController.getFees(f.branch.Id, '2026-27', 1).rows.isEmpty()
      );
      CollegeFeeSetupService.FeeSave request = new CollegeFeeSetupService.FeeSave();
      request.courseId = f.branch.Id;
      request.academicYear = '2026-27';
      try {
        CollegeSetupController.saveFees(request);
        Assert.fail('View only');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('System Administrator'));
      }
    }
  }
}
