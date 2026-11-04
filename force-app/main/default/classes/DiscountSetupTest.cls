@IsTest
private class DiscountSetupTest {
  private static DiscountSetupService.DiscountRequest request(String code) {
    DiscountSetupService.DiscountRequest r = new DiscountSetupService.DiscountRequest();
    r.code = code;
    r.description = 'Second child in the family';
    r.discountType = 'Percentage';
    r.value = 10;
    r.feeType = 'Tuition';
    return r;
  }

  @IsTest
  static void createsListsAndChangesDiscounts() {
    User deployer = new User(Id = UserInfo.getUserId());
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Python for Kids');
      DiscountSetupService.DiscountRequest r = request(' sibling 10 ');
      r.branchId = branch.Id;
      r.courseId = course.Id;
      r.maxUses = 50;
      r.requiresApproval = true;
      Test.startTest();
      Id id = DiscountSetupController.saveDiscount(r);
      Discount__c saved = [
        SELECT Code__c, Active__c, Requires_Approval__c
        FROM Discount__c
        WHERE Id = :id
      ];
      Assert.areEqual('SIBLING10', saved.Code__c, 'Code tidied');
      Assert.isTrue(saved.Active__c, 'Active by default');

      // An enrolment using it, waiting for approval.
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      Account learner = PersonAccountService.buildPerson(
        'Ira',
        'Shah',
        null,
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      learner = [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id = :learner.Id
      ];
      // As the deployer: enrolment fields are system-managed.
      System.runAs(deployer) {
        insert new CourseOfferingParticipant(
          CourseOfferingId = offering.Id,
          ParticipantContactId = learner.PersonContactId,
          ParticipantAccountId = learner.Id,
          ParticipationStatus = 'Enrolled',
          Discount__c = id,
          Discount_Approval_Status__c = 'Pending',
          Agreed_Discount__c = 250
        );
        update new Discount__c(Id = id, Times_Used__c = 1);
      }

      DiscountSetupService.Overview o = DiscountSetupController.getOverview();
      Test.stopTest();
      Assert.isTrue(o.canEdit, 'Administrators edit');
      Assert.areEqual(1, o.discounts.size(), 'Listed');
      DiscountSetupService.DiscountRow row = o.discounts[0];
      Assert.areEqual('Active', row.status, 'Status');
      Assert.areEqual(1, row.timesUsed, 'Times used');
      Assert.areEqual(1, row.enrolments, 'Enrolments');
      Assert.areEqual(250, row.amountGiven, 'Amount given');
      Assert.areEqual(1, row.pendingApprovals, 'Waiting for approval');
      Assert.areEqual(branch.Name, row.branch, 'Branch');
      Assert.isFalse(o.branches.isEmpty(), 'Branches offered');

      r.id = id;
      r.code = 'SIBLING10';
      r.value = 15;
      DiscountSetupController.saveDiscount(r);
      Assert.areEqual(
        15,
        [SELECT Value__c FROM Discount__c WHERE Id = :id].Value__c,
        'Changed'
      );
      DiscountSetupController.setActive(id, false);
      Assert.areEqual(
        'Inactive',
        DiscountSetupService.overview().discounts[0].status,
        'Switched off'
      );
    }
  }

  @IsTest
  static void refusesBadDiscounts() {
    System.runAs(TestDataFactory.admin()) {
      insert new Discount__c(
        Code__c = 'EARLY5',
        Discount_Type__c = 'Percentage',
        Value__c = 5,
        Active__c = true
      );
      DiscountSetupService.DiscountRequest dup = request('early5');
      DiscountSetupService.DiscountRequest blank = request('  ');
      DiscountSetupService.DiscountRequest odd = request('A!');
      DiscountSetupService.DiscountRequest big = request('BIG');
      big.value = 120;
      DiscountSetupService.DiscountRequest zero = request('ZERO');
      zero.value = 0;
      DiscountSetupService.DiscountRequest kind = request('KIND');
      kind.discountType = 'Voucher';
      DiscountSetupService.DiscountRequest dates = request('DATES');
      dates.validFrom = Date.today();
      dates.validTo = Date.today().addDays(-1);
      DiscountSetupService.DiscountRequest uses = request('USES');
      uses.maxUses = 0;
      for (
        DiscountSetupService.DiscountRequest bad : new List<DiscountSetupService.DiscountRequest>{
          dup,
          blank,
          odd,
          big,
          zero,
          kind,
          dates,
          uses
        }
      ) {
        try {
          DiscountSetupService.save(bad);
          Assert.fail('Expected a refusal for ' + bad.code);
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      DiscountSetupService.DiscountRequest fixedAmount = request('FLAT500');
      fixedAmount.discountType = 'Fixed Amount';
      fixedAmount.value = 500;
      Assert.isNotNull(
        DiscountSetupService.save(fixedAmount),
        'Fixed amounts above 100 are fine'
      );
    }
    Date today = Date.today();
    Assert.areEqual(
      'Expired',
      DiscountSetupService.status(
        new Discount__c(Active__c = true, Valid_To__c = today.addDays(-1)),
        today
      ),
      'Expired'
    );
    Assert.areEqual(
      'Scheduled',
      DiscountSetupService.status(
        new Discount__c(Active__c = true, Valid_From__c = today.addDays(1)),
        today
      ),
      'Scheduled'
    );
    Assert.areEqual(
      'Used up',
      DiscountSetupService.status(
        new Discount__c(Active__c = true, Max_Uses__c = 2, Times_Used__c = 2),
        today
      ),
      'Used up'
    );
  }

  @IsTest
  static void teachersCannotChangeDiscounts() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        DiscountSetupController.saveDiscount(request('TEACH'));
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        Assert.isFalse(
          DiscountSetupController.getOverview().canEdit,
          'Teachers may see codes but not change them'
        );
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        DiscountSetupController.setActive(null, false);
        Assert.fail('Refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
    }
  }
}
