@IsTest
private class CreditServiceTest {
  /**
   * Learner with a fee-paying guardian, enrolled in class A and invoiced 7,080
   * (1,000 admission + 5,000 term tuition + 18% tax); class B of the same
   * course is open for a second enrolment.
   */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Chemistry');
      insert new List<Fee_Price__c>{
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Admission',
          Billing_Frequency__c = 'One-time',
          Amount__c = 1000,
          Effective_From__c = Date.today().addDays(-10)
        ),
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Term',
          Amount__c = 5000,
          Effective_From__c = Date.today().addDays(-10)
        )
      };
      CourseOffering classA = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      CourseOffering classB = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(Id = classB.Id, Name = 'Credit Class B');
      Account learner = PersonAccountService.buildPerson(
        'Tara',
        'Credit' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      );
      Account guardian = PersonAccountService.buildPerson(
        'Vikram',
        'Credit' + Crypto.getRandomInteger(),
        'vikram.credit@example.com',
        null,
        branch.Id,
        'Guardian'
      );
      insert new List<Account>{ learner, guardian };
      Map<Id, Account> people = new Map<Id, Account>(
        [
          SELECT Id, PersonContactId
          FROM Account
          WHERE Id IN :new List<Id>{ learner.Id, guardian.Id }
        ]
      );
      GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
      link.guardianContactId = people.get(guardian.Id).PersonContactId;
      link.learnerContactId = people.get(learner.Id).PersonContactId;
      link.relationship = 'Mother';
      GuardianRelationshipService.link(
        new List<GuardianRelationshipService.GuardianLink>{ link }
      );
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = classA.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      BillingService.createInvoice(enrolmentId, true);
    }
  }

  private static Student_Invoice__c invoiceA() {
    return [
      SELECT Id, Name, Bill_To__c, Learner_Account__c, Total__c
      FROM Student_Invoice__c
      LIMIT 1
    ];
  }

  private static Id enrolInClassB() {
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = invoiceA().Learner_Account__c;
    request.offeringId = [
      SELECT Id
      FROM CourseOffering
      WHERE Name = 'Credit Class B'
    ]
    .Id;
    return EnrolmentService.enrol(request).enrolmentId;
  }

  private static BillingService.PaymentResult pay(
    Id invoiceId,
    Decimal amount
  ) {
    BillingService.PaymentRequest request = new BillingService.PaymentRequest();
    request.invoiceId = invoiceId;
    request.amount = amount;
    request.method = 'UPI';
    request.reference = 'UPI-' + amount;
    return BillingService.recordPayment(request);
  }

  private static Credit_Note__c note(Id noteId) {
    return [
      SELECT
        Name,
        Origin__c,
        Status__c,
        Amount__c,
        Amount_Applied__c,
        Amount_Refunded__c,
        Balance__c,
        Bill_To__c
      FROM Credit_Note__c
      WHERE Id = :noteId
    ];
  }

  private static CreditService.CreditRequest credit(
    Id invoiceId,
    Decimal amount,
    String origin
  ) {
    CreditService.CreditRequest request = new CreditService.CreditRequest();
    request.sourceInvoiceId = invoiceId;
    request.amount = amount;
    request.origin = origin;
    request.reason = 'Left after the first month';
    return request;
  }

  private static Id refund(Id noteId, Decimal amount) {
    CreditService.RefundRequest request = new CreditService.RefundRequest();
    request.creditNoteId = noteId;
    request.amount = amount;
    request.method = 'Bank Transfer';
    request.reason = 'Family asked for the money back';
    return CreditController.requestRefund(request);
  }

  private static Refund__c refundRecord(Id refundId) {
    return [
      SELECT
        Status__c,
        Auto_Approved__c,
        Approved_By__c,
        Paid_On__c,
        Reference__c
      FROM Refund__c
      WHERE Id = :refundId
    ];
  }

  @IsTest
  static void overpaymentBecomesCreditAndPaysTheNextInvoice() {
    System.runAs(TestDataFactory.admin()) {
      Student_Invoice__c a = invoiceA();
      BillingService.PaymentResult paid = pay(a.Id, 8080);
      Assert.areEqual('Exception', paid.reconciliationStatus, '1,000 too much');

      Test.startTest();
      Id noteId = CreditController.holdOverpayment(paid.paymentId);
      Credit_Note__c held = note(noteId);
      Assert.areEqual('Overpayment', held.Origin__c, 'Origin');
      Assert.areEqual(1000, held.Amount__c, 'Unallocated amount held');
      Assert.areEqual(a.Bill_To__c, held.Bill_To__c, 'Owed to the payer');
      Student_Payment__c payment = [
        SELECT Reconciliation_Status__c, Reconciliation_Note__c
        FROM Student_Payment__c
        WHERE Id = :paid.paymentId
      ];
      Assert.areEqual('Reconciled', payment.Reconciliation_Status__c, 'Closed');
      Assert.isTrue(
        payment.Reconciliation_Note__c.contains(held.Name),
        payment.Reconciliation_Note__c
      );
      try {
        CreditService.holdOverpayment(paid.paymentId);
        Assert.fail('Already settled');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('unallocated'), e.getMessage());
      }

      Id invoiceB = BillingService.createInvoice(enrolInClassB(), true);
      Student_Invoice__c b = [
        SELECT Status__c, Amount_Paid__c, Balance_Due__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceB
      ];
      Assert.areEqual(1000, b.Amount_Paid__c, 'Credit applied automatically');
      Assert.areEqual('Partially Paid', b.Status__c, 'Partly covered');
      Assert.areEqual(6080, b.Balance_Due__c, 'Rest to pay');
      held = note(noteId);
      Assert.areEqual('Used', held.Status__c, 'Credit used up');
      Assert.areEqual(0, held.Balance__c, 'No balance');
      Student_Payment__c applied = [
        SELECT Method__c, Receipt_Number__c, Reconciliation_Status__c
        FROM Student_Payment__c
        WHERE Credit_Note__c = :noteId
      ];
      Assert.areEqual('Credit Note', applied.Method__c, 'Credit payment');
      Assert.isNull(applied.Receipt_Number__c, 'No cash receipt');
      Assert.areEqual(
        8080,
        BillingService.financeDesk().collectedThisMonth,
        'Collections count cash only'
      );
      CreditService.CreditView view = CreditController.getCreditNote(noteId);
      Assert.areEqual(1, view.applications.size(), 'Application listed');
      Assert.areEqual(0, view.available, 'Nothing available');
      Assert.areEqual(
        1,
        CreditController.getLearnerCredits(a.Learner_Account__c).size(),
        'Learner credit notes'
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void refundsNeedApprovalAboveTheLimit() {
    AppSettings.overrides.put('Refund_Auto_Approve_Limit', '1000');
    User manager = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Branch_Manager')
    );
    Id noteId;
    Id large;
    Id small;
    System.runAs(TestDataFactory.admin()) {
      Student_Invoice__c a = invoiceA();
      pay(a.Id, 7080);
      Test.startTest();
      noteId = CreditController.issueCreditNote(
        credit(a.Id, 3000, 'Withdrawal')
      );
      Assert.areEqual(
        'Withdrawal',
        note(noteId).Origin__c,
        'Withdrawal credit'
      );
      try {
        CreditService.issueForInvoice(credit(a.Id, 5000, 'Goodwill'));
        Assert.fail('Cannot credit more than was paid');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('At most 4080'), e.getMessage());
      }

      Id quick = refund(noteId, 500);
      Refund__c auto = refundRecord(quick);
      Assert.areEqual('Approved', auto.Status__c, 'Within the limit');
      Assert.isTrue(auto.Auto_Approved__c, 'Auto-approved');
      try {
        CreditService.markRefundPaid(quick, null, null);
        Assert.fail('Reference needed');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('reference'), e.getMessage());
      }
      CreditController.markRefundPaid(quick, 'NEFT-001', Date.today());
      Credit_Note__c after = note(noteId);
      Assert.areEqual(500, after.Amount_Refunded__c, 'Refunded');
      Assert.areEqual('Partially Used', after.Status__c, 'Partly used');

      large = refund(noteId, 2000);
      Assert.areEqual(
        'Requested',
        refundRecord(large).Status__c,
        'Needs approval'
      );
      try {
        refund(noteId, 600);
        Assert.fail('Pending refunds reserve the balance');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('500'), e.getMessage());
      }
      try {
        CreditService.approveRefund(large);
        Assert.fail('Requester cannot approve');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('someone other'), e.getMessage());
      }
      CreditService.RefundQueue queue = CreditController.getRefundQueue();
      Assert.areEqual(
        1,
        queue.awaitingApproval.size(),
        'In the approval queue'
      );
      Assert.areEqual(2500, queue.openCreditTotal, 'Open credit');
      small = refund(noteId, 400);
    }
    System.runAs(manager) {
      CreditController.approveRefund(large);
      CreditController.rejectRefund(small, 'Duplicate request');
    }
    System.runAs(TestDataFactory.admin()) {
      Refund__c approved = refundRecord(large);
      Assert.areEqual('Approved', approved.Status__c, 'Approved');
      Assert.areEqual(manager.Id, approved.Approved_By__c, 'By the manager');
      Assert.areEqual('Rejected', refundRecord(small).Status__c, 'Rejected');
      CreditService.markRefundPaid(large, 'NEFT-002', null);
      Credit_Note__c after = note(noteId);
      Assert.areEqual(2500, after.Amount_Refunded__c, 'Both payouts');
      Assert.areEqual(500, after.Balance__c, 'Balance left');
      Assert.areEqual(
        500,
        CreditService.getCreditNote(noteId).available,
        'Rejected refund releases its reservation'
      );
      try {
        CreditService.voidNote(noteId, 'Mistake');
        Assert.fail('Used credit cannot be voided');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('unused'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void manualApplicationAndVoid() {
    AppSettings.overrides.put('Auto_Apply_Credit', 'false');
    System.runAs(TestDataFactory.admin()) {
      Student_Invoice__c a = invoiceA();
      pay(a.Id, 7080);
      Id noteId = CreditService.issueForInvoice(credit(a.Id, 1000, 'Goodwill'));
      Test.startTest();
      Id invoiceB = BillingService.createInvoice(enrolInClassB(), false);
      try {
        CreditService.apply(noteId, invoiceB, null);
        Assert.fail('Draft invoices cannot take credit');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('issued invoice'),
          e.getMessage()
        );
      }
      BillingService.issue(invoiceB);
      Assert.areEqual(
        0,
        [SELECT Amount_Paid__c FROM Student_Invoice__c WHERE Id = :invoiceB]
        .Amount_Paid__c,
        'Auto-apply switched off'
      );
      Assert.areEqual(
        400,
        CreditController.applyCredit(noteId, invoiceB, 400),
        'Part applied'
      );
      try {
        CreditService.apply(noteId, invoiceB, 700);
        Assert.fail('More than available');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('600'), e.getMessage());
      }
      Assert.areEqual(600, CreditService.apply(noteId, invoiceB, null), 'Rest');
      Assert.areEqual('Used', note(noteId).Status__c, 'Used up');
      try {
        CreditService.apply(noteId, invoiceB, null);
        Assert.fail('Nothing left');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('no balance'), e.getMessage());
      }

      Id spare = CreditService.issueForInvoice(credit(a.Id, 100, 'Other'));
      CreditController.voidCreditNote(spare, 'Raised by mistake');
      Credit_Note__c voided = note(spare);
      Assert.areEqual('Void', voided.Status__c, 'Voided');
      Assert.areEqual(0, voided.Balance__c, 'Void has no balance');
      try {
        CreditService.issueForInvoice(credit(invoiceB, 1500, 'Goodwill'));
        Assert.fail('Only paid money can be credited');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('At most 1000'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void validationAndControllerErrors() {
    System.runAs(TestDataFactory.admin()) {
      Id fakeNote = TestUtil.fakeId(Credit_Note__c.SObjectType);
      Id fakeRefund = TestUtil.fakeId(Refund__c.SObjectType);
      Id fakeInvoice = TestUtil.fakeId(Student_Invoice__c.SObjectType);
      Integer failures = 0;
      for (Integer i = 0; i < 9; i++) {
        try {
          switch on i {
            when 0 {
              CreditController.issueCreditNote(credit(null, 1, null));
            }
            when 1 {
              CreditController.issueCreditNote(credit(fakeInvoice, 0, null));
            }
            when 2 {
              CreditController.issueCreditNote(
                credit(fakeInvoice, 1, 'Transfer')
              );
            }
            when 3 {
              CreditController.holdOverpayment(
                TestUtil.fakeId(Student_Payment__c.SObjectType)
              );
            }
            when 4 {
              CreditController.voidCreditNote(fakeNote, null);
            }
            when 5 {
              CreditController.applyCredit(fakeNote, fakeInvoice, -1);
            }
            when 6 {
              CreditController.approveRefund(fakeRefund);
            }
            when 7 {
              CreditController.rejectRefund(fakeRefund, null);
            }
            when 8 {
              CreditController.getCreditNote(fakeNote);
            }
          }
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Assert.areEqual(9, failures, 'Every call reports a friendly error');
      Integer refundFailures = 0;
      for (Integer i = 0; i < 4; i++) {
        CreditService.RefundRequest request = new CreditService.RefundRequest();
        request.creditNoteId = i == 0 ? null : fakeNote;
        request.amount = i == 1 ? 0 : 10;
        request.method = i == 2 ? null : 'UPI';
        request.reason = i == 3 ? null : 'x';
        try {
          CreditService.requestRefund(request);
        } catch (AppException e) {
          refundFailures++;
        }
      }
      Assert.areEqual(4, refundFailures, 'Refund requests are validated');
      Assert.areEqual('Open', CreditService.statusFor(100, 0, 0), 'Open');
      Assert.areEqual(
        'Partially Used',
        CreditService.statusFor(100, 30, 20),
        'Partly'
      );
      Assert.areEqual('Used', CreditService.statusFor(100, 60, 40), 'Used');
    }
  }

  @IsTest
  static void ledgerRecordsAreProtected() {
    System.runAs(TestDataFactory.admin()) {
      Student_Invoice__c a = invoiceA();
      List<Credit_Note__c> notes = new List<Credit_Note__c>{
        new Credit_Note__c(
          Bill_To__c = a.Bill_To__c,
          Amount__c = 100,
          Amount_Applied__c = 40,
          Amount_Refunded__c = 0,
          Status__c = 'Partially Used'
        ),
        new Credit_Note__c(
          Bill_To__c = a.Bill_To__c,
          Amount__c = 100,
          Amount_Applied__c = 0,
          Amount_Refunded__c = 0,
          Status__c = 'Open'
        )
      };
      Database.insert(notes, AccessLevel.SYSTEM_MODE);
      Refund__c paid = new Refund__c(
        Credit_Note__c = notes[0].Id,
        Amount__c = 10,
        Status__c = 'Paid'
      );
      Database.insert(paid, AccessLevel.SYSTEM_MODE);

      List<Database.DeleteResult> results = Database.delete(
        new List<Id>{ notes[0].Id, paid.Id },
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.isFalse(results[0].isSuccess(), 'Used credit is kept');
      Assert.isFalse(results[1].isSuccess(), 'Paid refund is kept');
      Assert.isTrue(
        Database.delete(notes[1].Id, false, AccessLevel.SYSTEM_MODE)
          .isSuccess(),
        'An unused credit note can be deleted'
      );
      Database.SaveResult jump = Database.update(
        new Credit_Note__c(Id = notes[0].Id, Status__c = 'Void'),
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.isFalse(jump.isSuccess(), 'Used credit cannot be voided');
      Database.SaveResult back = Database.update(
        new Refund__c(Id = paid.Id, Status__c = 'Requested'),
        false,
        AccessLevel.SYSTEM_MODE
      );
      Assert.isFalse(back.isSuccess(), 'A paid refund cannot be reopened');
    }
  }
}
