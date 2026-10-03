@IsTest
private class BillingServiceTest {
  private class Fixture {
    Branch__c branch;
    LearningCourse course;
    Account learner;
    Account guardian;
    Id learnerContactId;
    Id guardianContactId;
    Id enrolmentId;
  }

  /** Learner with a fee-paying guardian, enrolled at 7080 (1000 + 5000 + 18% tax). */
  private static Fixture fixture() {
    TestDataFactory.createReferenceData();
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    f.course = TestDataFactory.createCourse('Physics');
    insert new List<Fee_Price__c>{
      new Fee_Price__c(
        Learning_Course__c = f.course.Id,
        Fee_Type__c = 'Admission',
        Billing_Frequency__c = 'One-time',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-10)
      ),
      new Fee_Price__c(
        Learning_Course__c = f.course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 5000,
        Effective_From__c = Date.today().addDays(-10)
      )
    };
    f.learner = PersonAccountService.buildPerson(
      'Meera',
      'Bill' + Crypto.getRandomInteger(),
      null,
      null,
      f.branch.Id,
      'Learner'
    );
    f.guardian = PersonAccountService.buildPerson(
      'Ravi',
      'Payer' + Crypto.getRandomInteger(),
      'ravi.payer@example.com',
      null,
      f.branch.Id,
      'Guardian'
    );
    insert new List<Account>{ f.learner, f.guardian };
    Map<Id, Account> people = new Map<Id, Account>(
      [
        SELECT Id, PersonContactId
        FROM Account
        WHERE Id IN :new List<Id>{ f.learner.Id, f.guardian.Id }
      ]
    );
    f.learnerContactId = people.get(f.learner.Id).PersonContactId;
    f.guardianContactId = people.get(f.guardian.Id).PersonContactId;
    GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
    link.guardianContactId = f.guardianContactId;
    link.learnerContactId = f.learnerContactId;
    link.relationship = 'Father';
    GuardianRelationshipService.link(
      new List<GuardianRelationshipService.GuardianLink>{ link }
    );
    f.enrolmentId = enrol(f, f.learner.Id);
    return f;
  }

  private static Id enrol(Fixture f, Id learnerAccountId) {
    CourseOffering offering = TestDataFactory.createOffering(
      f.course.Id,
      f.branch.Id,
      10
    );
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = learnerAccountId;
    request.offeringId = offering.Id;
    return EnrolmentService.enrol(request).enrolmentId;
  }

  private static BillingService.PaymentResult pay(
    Id invoiceId,
    Decimal amount,
    String method
  ) {
    BillingService.PaymentRequest request = new BillingService.PaymentRequest();
    request.invoiceId = invoiceId;
    request.amount = amount;
    request.method = method;
    request.reference = 'REF-' + amount;
    return BillingController.recordPayment(request);
  }

  private static Student_Invoice__c invoice(Id invoiceId) {
    return [
      SELECT
        Name,
        Status__c,
        Bill_To__c,
        Learner__c,
        Learner_Account__c,
        Issue_Date__c,
        Due_Date__c,
        Subtotal__c,
        Tax_Total__c,
        Total__c,
        Amount_Paid__c,
        Balance_Due__c,
        Enrolment__r.Billing_Status__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
    ];
  }

  private static Student_Payment__c payment(Id paymentId) {
    return [
      SELECT
        Status__c,
        Reconciliation_Status__c,
        Reconciliation_Note__c,
        Receipt_Number__c,
        Allocated_Amount__c,
        Unallocated_Amount__c,
        Payer__c,
        Reconciled_By__c
      FROM Student_Payment__c
      WHERE Id = :paymentId
    ];
  }

  @IsTest
  static void invoicesEnrolmentToFeePayer() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id invoiceId = BillingController.createInvoice(f.enrolmentId, true);
      Student_Invoice__c inv = invoice(invoiceId);
      Assert.isTrue(inv.Name.startsWith('TST-'), 'Branch prefix: ' + inv.Name);
      Assert.areEqual('Issued', inv.Status__c, 'Issued now');
      Assert.areEqual(f.guardianContactId, inv.Bill_To__c, 'Fee payer billed');
      Assert.areEqual(f.learnerContactId, inv.Learner__c, 'Learner');
      Assert.areEqual(f.learner.Id, inv.Learner_Account__c, 'Learner account');
      Assert.areEqual(
        Date.today().addDays(10),
        inv.Due_Date__c,
        'Branch due days'
      );
      Assert.areEqual(6000, inv.Subtotal__c, 'Subtotal');
      Assert.areEqual(1080, inv.Tax_Total__c, 'Tax');
      Assert.areEqual(7080, inv.Total__c, 'Total equals agreed price');
      Assert.areEqual(7080, inv.Balance_Due__c, 'Nothing paid');
      Assert.areEqual(
        'Invoiced',
        inv.Enrolment__r.Billing_Status__c,
        'Enrolment invoiced'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Enrolment_Fee_Line__c
          WHERE Enrolment__c = :f.enrolmentId AND Invoiced__c = FALSE
        ],
        'All fee lines invoiced'
      );
      try {
        BillingService.createInvoice(f.enrolmentId, true);
        Assert.fail('Nothing left to invoice');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('nothing left'), e.getMessage());
      }
      BillingService.InvoiceView view = BillingController.getInvoice(invoiceId);
      Assert.areEqual(2, view.lines.size(), 'Two lines');
      Assert.isTrue(view.canManage, 'Administrator manages billing');
      Assert.areEqual(
        1,
        BillingController.getLearnerInvoices(f.learner.Id).size(),
        'Learner invoices'
      );
    }
  }

  @IsTest
  static void partialThenFullPaymentReconciles() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id invoiceId = BillingService.createInvoice(f.enrolmentId, true);
      BillingService.PaymentResult first = pay(invoiceId, 3000, 'Cash');
      Assert.areEqual('Confirmed', first.status, 'Cash is confirmed');
      Assert.areEqual(
        'Reconciled',
        first.reconciliationStatus,
        'Fully allocated'
      );
      Assert.isTrue(first.receiptNumber.startsWith('RCT-'), 'Receipt issued');
      Assert.areEqual(3000, first.allocated, 'Allocated');
      Student_Invoice__c inv = invoice(invoiceId);
      Assert.areEqual('Partially Paid', inv.Status__c, 'Partially paid');
      Assert.areEqual(4080, inv.Balance_Due__c, 'Balance');
      Assert.areEqual(
        'Partially Paid',
        inv.Enrolment__r.Billing_Status__c,
        'Enrolment partially paid'
      );
      Assert.areEqual(
        f.guardianContactId,
        payment(first.paymentId).Payer__c,
        'Payer defaults to bill-to'
      );

      pay(invoiceId, 4080, 'UPI');
      inv = invoice(invoiceId);
      Assert.areEqual('Paid', inv.Status__c, 'Paid');
      Assert.areEqual(0, inv.Balance_Due__c, 'Settled');
      Assert.areEqual(
        'Paid',
        inv.Enrolment__r.Billing_Status__c,
        'Enrolment paid'
      );

      BillingService.FinanceDesk desk = BillingController.getFinanceDesk();
      Assert.areEqual(7080, desk.collectedThisMonth, 'Collected this month');
      Assert.areEqual(0, desk.outstanding, 'Nothing outstanding');
    }
  }

  @IsTest
  static void overpaymentRaisesExceptionUntilResolved() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id invoiceId = BillingService.createInvoice(f.enrolmentId, true);
      BillingService.PaymentResult result = pay(
        invoiceId,
        8000,
        'Bank Transfer'
      );
      Assert.areEqual('Exception', result.reconciliationStatus, 'Overpayment');
      Assert.areEqual(920, result.unallocated, 'Remainder');
      Assert.areEqual(
        'Paid',
        invoice(invoiceId).Status__c,
        'Invoice still paid in full'
      );
      Assert.areEqual(
        1,
        BillingService.financeDesk().exceptions.size(),
        'Desk lists exception'
      );
      try {
        BillingController.resolveException(result.paymentId, null);
        Assert.fail('A note is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('unallocated'), e.getMessage());
      }
      // A new invoice for the same payer absorbs the credit on retry.
      Id second = BillingService.createInvoice(enrol(f, f.learner.Id), true);
      BillingService.PaymentResult retried = BillingService.resolveException(
        result.paymentId,
        null
      );
      Assert.areEqual(
        'Reconciled',
        retried.reconciliationStatus,
        'Allocated to new invoice'
      );
      Assert.areEqual(920, invoice(second).Amount_Paid__c, 'Credit applied');
      Assert.areEqual(
        'Partially Paid',
        invoice(second).Status__c,
        'Second partially paid'
      );
    }
  }

  @IsTest
  static void closesExceptionWithNote() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id invoiceId = BillingService.createInvoice(f.enrolmentId, true);
      BillingService.PaymentResult result = pay(invoiceId, 7100, 'Card');
      BillingService.PaymentResult closed = BillingService.resolveException(
        result.paymentId,
        'Refunded 20 in cash'
      );
      Assert.areEqual('Reconciled', closed.reconciliationStatus, 'Closed');
      Student_Payment__c p = payment(result.paymentId);
      Assert.areEqual(
        'Refunded 20 in cash',
        p.Reconciliation_Note__c,
        'Note kept'
      );
      Assert.areEqual(
        UserInfo.getUserId(),
        p.Reconciled_By__c,
        'Reconciler stamped'
      );
      try {
        BillingService.resolveException(result.paymentId, 'again');
        Assert.fail('No exception left');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('no reconciliation exception'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void allocatesOldestDueFirstForPayer() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id first = BillingService.createInvoice(f.enrolmentId, true);
      Id second = BillingService.createInvoice(enrol(f, f.learner.Id), true);
      Database.update(
        new Student_Invoice__c(
          Id = first,
          Due_Date__c = Date.today().addDays(-3)
        ),
        AccessLevel.SYSTEM_MODE
      );
      BillingService.PaymentRequest request = new BillingService.PaymentRequest();
      request.payerContactId = f.guardianContactId;
      request.amount = 7180;
      request.method = 'Cash';
      BillingService.PaymentResult result = BillingService.recordPayment(
        request
      );
      Assert.areEqual(
        'Reconciled',
        result.reconciliationStatus,
        'Fully allocated'
      );
      Assert.areEqual(
        'Paid',
        invoice(first).Status__c,
        'Oldest due paid first'
      );
      Assert.areEqual(100, invoice(second).Amount_Paid__c, 'Remainder to next');
    }
  }

  @IsTest
  static void pendingPaymentsConfirmOrFail() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id invoiceId = BillingService.createInvoice(f.enrolmentId, true);
      BillingService.PaymentRequest request = new BillingService.PaymentRequest();
      request.invoiceId = invoiceId;
      request.amount = 2000;
      request.method = 'Cheque';
      request.confirmed = false;
      BillingService.PaymentResult cheque = BillingService.recordPayment(
        request
      );
      Assert.areEqual('Pending', cheque.status, 'Awaiting clearance');
      Assert.areEqual(
        'Issued',
        invoice(invoiceId).Status__c,
        'Nothing allocated yet'
      );
      Assert.areEqual(
        1,
        BillingService.getInvoice(invoiceId).pendingPayments.size(),
        'Pending listed'
      );
      BillingService.PaymentResult cleared = BillingController.confirmPayment(
        cheque.paymentId
      );
      Assert.areEqual(
        'Reconciled',
        cleared.reconciliationStatus,
        'Allocated on clearance'
      );
      Assert.isNotNull(cleared.receiptNumber, 'Receipt on confirmation');

      request.amount = 500;
      BillingService.PaymentResult bounced = BillingService.recordPayment(
        request
      );
      BillingController.failPayment(bounced.paymentId, 'Cheque bounced');
      Student_Payment__c failed = payment(bounced.paymentId);
      Assert.areEqual('Failed', failed.Status__c, 'Failed');
      Assert.areEqual(
        'Cheque bounced',
        failed.Reconciliation_Note__c,
        'Reason'
      );
      Assert.areEqual(
        2000,
        invoice(invoiceId).Amount_Paid__c,
        'Failed payment not allocated'
      );
      try {
        BillingService.confirmPayment(bounced.paymentId);
        Assert.fail('Failed payments cannot be confirmed');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('pending'), e.getMessage());
      }
    }
  }

  @IsTest
  static void cancelsDraftsAndGuardsTheLedger() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id draft = BillingService.createInvoice(f.enrolmentId, false);
      Assert.areEqual('Draft', invoice(draft).Status__c, 'Draft');
      try {
        pay(draft, 100, 'Cash');
        Assert.fail('No payments on drafts');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('issued invoices'),
          e.getMessage()
        );
      }
      BillingController.cancelInvoice(draft, 'Wrong learner');
      Assert.areEqual('Cancelled', invoice(draft).Status__c, 'Cancelled');
      Assert.areEqual(
        'Not Invoiced',
        [
          SELECT Billing_Status__c
          FROM CourseOfferingParticipant
          WHERE Id = :f.enrolmentId
        ]
        .Billing_Status__c,
        'Enrolment released'
      );

      Id reissued = BillingService.createInvoice(f.enrolmentId, false);
      BillingController.issueInvoice(reissued);
      Assert.areEqual('Issued', invoice(reissued).Status__c, 'Issued');
      pay(reissued, 100, 'Cash');
      try {
        BillingService.cancel(reissued, 'Mistake');
        Assert.fail('Paid invoices cannot be cancelled');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('unpaid issued invoices'),
          e.getMessage()
        );
      }
      try {
        delete new Student_Invoice__c(Id = reissued);
        Assert.fail('Issued invoices cannot be deleted');
      } catch (DmlException e) {
        Assert.isTrue(
          e.getMessage().contains('Cancel the invoice'),
          e.getMessage()
        );
      }
      try {
        BillingService.issue(reissued);
        Assert.fail('Only drafts are issued');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('draft'), e.getMessage());
      }
      try {
        Database.update(
          new Student_Invoice__c(Id = reissued, Status__c = 'Draft'),
          AccessLevel.SYSTEM_MODE
        );
        Assert.fail('Undeclared transition');
      } catch (DmlException e) {
        Assert.isTrue(
          e.getMessage().contains('Partially Paid'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void protectsLedgerRecords() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Id draft = BillingService.createInvoice(f.enrolmentId, false);
      BillingService.cancel(draft, 'Duplicate');
      Id invoiceId = BillingService.createInvoice(f.enrolmentId, true);
      BillingService.PaymentResult paid = pay(invoiceId, 500, 'Cash');
      try {
        Database.delete(paid.paymentId, AccessLevel.SYSTEM_MODE);
        Assert.fail('Confirmed payments are kept');
      } catch (DmlException e) {
        Assert.isTrue(
          e.getMessage().contains('cannot be deleted'),
          e.getMessage()
        );
      }
      try {
        Database.update(
          new Student_Payment__c(Id = paid.paymentId, Status__c = 'Pending'),
          AccessLevel.SYSTEM_MODE
        );
        Assert.fail('Confirmed payments stay confirmed');
      } catch (DmlException e) {
        Assert.isTrue(e.getMessage().contains('Confirmed'), e.getMessage());
      }
      BillingService.PaymentRequest request = new BillingService.PaymentRequest();
      request.invoiceId = invoiceId;
      request.amount = 50;
      request.method = 'Cheque';
      request.confirmed = false;
      Id pendingId = BillingService.recordPayment(request).paymentId;
      Database.delete(pendingId, AccessLevel.SYSTEM_MODE);
      Id spare = BillingService.createInvoice(enrol(f, f.learner.Id), false);
      Database.delete(spare, AccessLevel.SYSTEM_MODE);
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Student_Invoice__c WHERE Id = :spare],
        'Drafts can be deleted'
      );
    }
  }

  @IsTest
  static void controllerReportsErrors() {
    System.runAs(TestDataFactory.admin()) {
      Id missing = TestUtil.fakeId(Student_Invoice__c.SObjectType);
      Id missingPayment = TestUtil.fakeId(Student_Payment__c.SObjectType);
      Id missingEnrolment = TestUtil.fakeId(
        CourseOfferingParticipant.SObjectType
      );
      Integer failures = 0;
      List<String> calls = new List<String>{
        'create',
        'issue',
        'cancel',
        'pay',
        'confirm',
        'fail',
        'resolve',
        'get'
      };
      for (String call : calls) {
        try {
          switch on call {
            when 'create' {
              BillingController.createInvoice(missingEnrolment, true);
            }
            when 'issue' {
              BillingController.issueInvoice(missing);
            }
            when 'cancel' {
              BillingController.cancelInvoice(missing, null);
            }
            when 'pay' {
              BillingController.recordPayment(
                new BillingService.PaymentRequest()
              );
            }
            when 'confirm' {
              BillingController.confirmPayment(missingPayment);
            }
            when 'fail' {
              BillingController.failPayment(missingPayment, 'x');
            }
            when 'resolve' {
              BillingController.resolveException(missingPayment, 'x');
            }
            when 'get' {
              BillingController.getInvoice(missing);
            }
          }
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Assert.areEqual(
        calls.size(),
        failures,
        'Every call reports a friendly error'
      );
    }
  }

  @IsTest
  static void requiresDiscountDecisionAndPermission() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    Fixture f;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
      Database.update(
        new CourseOfferingParticipant(
          Id = f.enrolmentId,
          Discount_Approval_Status__c = 'Pending'
        ),
        AccessLevel.SYSTEM_MODE
      );
      try {
        BillingService.createInvoice(f.enrolmentId, true);
        Assert.fail('Pending discount blocks invoicing');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('approval'), e.getMessage());
      }
    }
    System.runAs(teacher) {
      try {
        BillingService.createInvoice(f.enrolmentId, true);
        Assert.fail('Teachers cannot invoice');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
  }

  /** Amount_Paid__c is a roll-up, so build the record through JSON. */
  private static Student_Invoice__c paidInvoice() {
    return (Student_Invoice__c) JSON.deserialize(
      '{"attributes":{"type":"Student_Invoice__c"},"Status__c":"Paid","Amount_Paid__c":10}',
      Student_Invoice__c.class
    );
  }

  @IsTest
  static void derivesEnrolmentBillingStatus() {
    Assert.areEqual(
      'Not Invoiced',
      BillingService.billingStatus(new List<Student_Invoice__c>()),
      'None'
    );
    Assert.areEqual(
      'Invoiced',
      BillingService.billingStatus(
        new List<Student_Invoice__c>{
          new Student_Invoice__c(Status__c = 'Issued')
        }
      ),
      'Issued'
    );
    Assert.areEqual(
      'Partially Paid',
      BillingService.billingStatus(
        new List<Student_Invoice__c>{
          paidInvoice(),
          new Student_Invoice__c(Status__c = 'Issued')
        }
      ),
      'One of two paid'
    );
    Assert.areEqual(
      'Paid',
      BillingService.billingStatus(
        new List<Student_Invoice__c>{ paidInvoice() }
      ),
      'All paid'
    );
  }
}
