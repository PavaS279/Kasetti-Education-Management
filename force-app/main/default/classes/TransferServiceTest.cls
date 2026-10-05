@IsTest
private class TransferServiceTest {
  private class Fixture {
    Branch__c branch;
    CourseOffering fromClass;
    CourseOffering sameCourse;
    CourseOffering pricier;
    CourseOffering cheaper;
    Account learner;
    Id enrolmentId;
  }

  private static LearningCourse course(String name, Decimal amount) {
    LearningCourse c = TestDataFactory.createCourse(name);
    insert new Fee_Price__c(
      Learning_Course__c = c.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = amount,
      Effective_From__c = Date.today().addDays(-1)
    );
    return c;
  }

  /** Learner enrolled in a 1,000 class; other classes at 1,000, 1,500 and 600 (+18% tax). */
  private static Fixture fixture() {
    TestDataFactory.createReferenceData();
    DocumentService.suppressJobs = true;
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    LearningCourse base = course('Chess', 1000);
    f.fromClass = TestDataFactory.createOffering(base.Id, f.branch.Id, 1);
    f.sameCourse = TestDataFactory.createOffering(base.Id, f.branch.Id, 5);
    f.pricier = TestDataFactory.createOffering(
      course('Chess Advanced', 1500).Id,
      f.branch.Id,
      5
    );
    f.cheaper = TestDataFactory.createOffering(
      course('Chess Club', 600).Id,
      f.branch.Id,
      5
    );
    f.learner = PersonAccountService.buildPerson(
      'Tara',
      'Move' + Crypto.getRandomInteger(),
      null,
      null,
      f.branch.Id,
      'Learner'
    );
    insert f.learner;
    EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
    r.learnerAccountId = f.learner.Id;
    r.offeringId = f.fromClass.Id;
    f.enrolmentId = EnrolmentService.enrol(r).enrolmentId;
    return f;
  }

  private static TransferService.TransferRequest request(
    Id enrolmentId,
    Id targetId
  ) {
    TransferService.TransferRequest r = new TransferService.TransferRequest();
    r.enrolmentId = enrolmentId;
    r.targetOfferingId = targetId;
    r.reason = 'Timing change';
    return r;
  }

  private static CourseOfferingParticipant enrolment(Id enrolmentId) {
    return [
      SELECT
        ParticipationStatus,
        Transferred_To__c,
        Transferred_From__c,
        Transfer_Adjustment__c,
        Credit_Due__c,
        Billing_Status__c,
        Withdrawal_Reason__c,
        Agreed_Total__c,
        (SELECT Line_Total__c, Fee_Type__c FROM Fee_Lines__r)
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
    ];
  }

  @IsTest
  static void transfersBeforeInvoicingAndHandsTheSeatToTheWaitlist() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Account waiting = PersonAccountService.buildPerson(
        'Wait',
        'Er' + Crypto.getRandomInteger(),
        null,
        null,
        f.branch.Id,
        'Learner'
      );
      insert waiting;
      WaitlistService.JoinRequest j = new WaitlistService.JoinRequest();
      j.learnerAccountId = waiting.Id;
      j.offeringId = f.fromClass.Id;
      Id entryId = WaitlistService.join(j);
      Test.startTest();

      TransferService.TransferPreview preview = TransferController.previewTransfer(
        request(f.enrolmentId, f.sameCourse.Id)
      );
      Assert.areEqual(0, preview.difference, 'Same course, same price');
      Assert.isFalse(preview.alreadyInvoiced, 'Not invoiced');
      Assert.isTrue(
        preview.blockers.isEmpty(),
        String.valueOf(preview.blockers)
      );

      Id newId = TransferController.transfer(
        request(f.enrolmentId, f.sameCourse.Id)
      );
      CourseOfferingParticipant oldOne = enrolment(f.enrolmentId);
      CourseOfferingParticipant newOne = enrolment(newId);
      Assert.areEqual(
        'Withdrew',
        oldOne.ParticipationStatus,
        'Old enrolment ended'
      );
      Assert.areEqual(newId, oldOne.Transferred_To__c, 'Linked forward');
      Assert.isTrue(
        oldOne.Withdrawal_Reason__c.startsWith('Transferred to'),
        oldOne.Withdrawal_Reason__c
      );
      Assert.isTrue(oldOne.Fee_Lines__r.isEmpty(), 'Uninvoiced lines dropped');
      Assert.areEqual(
        'Enrolled',
        newOne.ParticipationStatus,
        'Enrolled in the new class'
      );
      Assert.areEqual(f.enrolmentId, newOne.Transferred_From__c, 'Linked back');
      Assert.areEqual(1, newOne.Fee_Lines__r.size(), 'Billed at its own price');
      Assert.areEqual(
        'Offered',
        [SELECT Status__c FROM Waitlist_Entry__c WHERE Id = :entryId].Status__c,
        'Freed seat offered to the waitlist'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void afterInvoicingBillsOnlyTheIncrease() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      BillingService.createInvoice(f.enrolmentId, true);
      Test.startTest();
      TransferService.TransferPreview preview = TransferService.preview(
        request(f.enrolmentId, f.pricier.Id)
      );
      Assert.areEqual(590, preview.difference, '1,770 - 1,180');
      Assert.isTrue(
        preview.billingOutcome.contains('only the difference'),
        preview.billingOutcome
      );

      Id newId = TransferService.transfer(request(f.enrolmentId, f.pricier.Id));
      CourseOfferingParticipant newOne = enrolment(newId);
      Assert.areEqual(
        590,
        newOne.Transfer_Adjustment__c,
        'Difference recorded'
      );
      Assert.areEqual(1, newOne.Fee_Lines__r.size(), 'One adjustment line');
      Assert.areEqual(
        590,
        newOne.Fee_Lines__r[0].Line_Total__c,
        'Only the increase'
      );
      Assert.areEqual(
        'Not Invoiced',
        newOne.Billing_Status__c,
        'Increase to invoice'
      );
      Id adjustment = BillingService.createInvoice(newId, true);
      Assert.areEqual(
        590,
        [SELECT Total__c FROM Student_Invoice__c WHERE Id = :adjustment]
        .Total__c,
        'Adjustment invoice'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void afterInvoicingRecordsCreditForADecrease() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      BillingService.createInvoice(f.enrolmentId, true);
      Test.startTest();
      Id newId = TransferService.transfer(request(f.enrolmentId, f.cheaper.Id));
      CourseOfferingParticipant newOne = enrolment(newId);
      Assert.areEqual(-472, newOne.Transfer_Adjustment__c, '708 - 1,180');
      Assert.areEqual(472, newOne.Credit_Due__c, 'Credit due to the family');
      Assert.isTrue(newOne.Fee_Lines__r.isEmpty(), 'Nothing more to bill');
      Assert.areEqual(
        'Invoiced',
        newOne.Billing_Status__c,
        'Covered by the original invoice'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void guardsTransfers() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Test.startTest();
      Map<String, TransferService.TransferRequest> cases = new Map<String, TransferService.TransferRequest>{
        'different class' => request(f.enrolmentId, f.fromClass.Id),
        'reason' => request(f.enrolmentId, f.sameCourse.Id)
      };
      cases.get('reason').reason = null;
      for (String expected : cases.keySet()) {
        try {
          TransferService.transfer(cases.get(expected));
          Assert.fail('Expected: ' + expected);
        } catch (AppException e) {
          Assert.isTrue(
            e.getMessage().containsIgnoreCase(expected),
            e.getMessage()
          );
        }
      }
      TransferService.TransferRequest early = request(
        f.enrolmentId,
        f.sameCourse.Id
      );
      early.effectiveDate = Date.today().addYears(-1);
      Assert.isFalse(
        TransferService.preview(early).blockers.isEmpty(),
        'Back-dated before start'
      );
      TransferService.transfer(request(f.enrolmentId, f.sameCourse.Id));
      try {
        TransferService.transfer(request(f.enrolmentId, f.cheaper.Id));
        Assert.fail('Already transferred');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('active'), e.getMessage());
      }
      try {
        TransferController.transfer(new TransferService.TransferRequest());
        Assert.fail('Missing input');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().length() > 0, 'Friendly error');
      }
      try {
        TransferController.previewTransfer(
          new TransferService.TransferRequest()
        );
        Assert.fail('Missing input');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().length() > 0, 'Friendly error');
      }
      Test.stopTest();
    }
  }
}
