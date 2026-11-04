@IsTest
private class RecurringBillingTest {
  /**
   * Learner enrolled in a class that started 7 days ago and runs 97 days:
   * admission 1000 one-time + tuition 2000 monthly, both with 18% tax.
   */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Coding Club');
      insert new List<Fee_Price__c>{
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Admission',
          Billing_Frequency__c = 'One-time',
          Amount__c = 1000,
          Effective_From__c = Date.today().addDays(-30)
        ),
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Monthly',
          Amount__c = 2000,
          Effective_From__c = Date.today().addDays(-30)
        )
      };
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      Account learner = PersonAccountService.buildPerson(
        'Ishaan',
        'Monthly' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      EnrolmentService.enrol(request);
    }
  }

  private static CourseOfferingParticipant enrolment() {
    return [
      SELECT Id, StartDate, EndDate
      FROM CourseOfferingParticipant
      WHERE CourseOffering.LearningCourse.Name = 'Coding Club'
      LIMIT 1
    ];
  }

  private static Enrolment_Fee_Line__c monthlyLine(Id enrolmentId) {
    return [
      SELECT Next_Bill_Date__c, Periods_Billed__c, Invoiced__c
      FROM Enrolment_Fee_Line__c
      WHERE Enrolment__c = :enrolmentId AND Billing_Frequency__c = 'Monthly'
    ];
  }

  private static Student_Invoice__c invoice(Id invoiceId) {
    return [
      SELECT
        Status__c,
        Total__c,
        Billing_Period__c,
        Due_Date__c,
        Original_Due_Date__c,
        Instalment_Count__c,
        Amount_Paid__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
    ];
  }

  @IsTest
  static void firstInvoiceBillsTheFirstMonthThenTheJobBillsEachPeriod() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Date start = e.StartDate;
      Id first = BillingController.createInvoice(e.Id, true);
      Student_Invoice__c inv = invoice(first);
      Assert.areEqual(3540, inv.Total__c, '1180 admission + 2360 first month');
      Assert.areEqual(
        BillingService.periodLabel(start),
        inv.Billing_Period__c,
        'Period label'
      );
      Invoice_Line__c periodLine = [
        SELECT Period_Start__c, Period_End__c, Description__c
        FROM Invoice_Line__c
        WHERE Student_Invoice__c = :first AND Period_Start__c != NULL
      ];
      Assert.areEqual(start, periodLine.Period_Start__c, 'Period start');
      Assert.areEqual(
        start.addMonths(1).addDays(-1),
        periodLine.Period_End__c,
        'Period end'
      );
      Assert.isTrue(
        periodLine.Description__c.contains(BillingService.periodLabel(start)),
        periodLine.Description__c
      );
      Enrolment_Fee_Line__c line = monthlyLine(e.Id);
      Assert.areEqual(start.addMonths(1), line.Next_Bill_Date__c, 'Next bill');
      Assert.areEqual(1, line.Periods_Billed__c, 'One period');
      Assert.isFalse(line.Invoiced__c, 'Still recurring');
      try {
        BillingService.createInvoice(e.Id, true);
        Assert.fail('Next period is not due yet');
      } catch (AppException ex) {
        Assert.isTrue(
          ex.getMessage().contains('Nothing is due yet'),
          ex.getMessage()
        );
      }

      Test.startTest();
      Database.executeBatch(new RecurringBillingJob(start.addMonths(1)), 20);
      Test.stopTest();

      List<Student_Invoice__c> raised = [
        SELECT Id, Status__c, Total__c, Billing_Period__c
        FROM Student_Invoice__c
        WHERE Enrolment__c = :e.Id AND Id != :first
      ];
      Assert.areEqual(1, raised.size(), 'Job raised the second invoice');
      Assert.areEqual('Issued', raised[0].Status__c, 'Issued automatically');
      Assert.areEqual(2360, raised[0].Total__c, 'One month of tuition');
      Assert.areEqual(
        BillingService.periodLabel(start.addMonths(1)),
        raised[0].Billing_Period__c,
        'Second period'
      );
      Assert.areEqual(2, monthlyLine(e.Id).Periods_Billed__c, 'Two periods');
    }
  }

  @IsTest
  static void cancellationStepsBackAndCatchUpStopsAtTheEndDate() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Date start = e.StartDate;
      BillingService.createInvoice(e.Id, true);
      Id second = BillingService.billDuePeriods(e.Id, start.addMonths(1));
      BillingController.cancelInvoice(second, 'Raised in error');
      Enrolment_Fee_Line__c line = monthlyLine(e.Id);
      Assert.areEqual(1, line.Periods_Billed__c, 'Period released');
      Assert.areEqual(
        start.addMonths(1),
        line.Next_Bill_Date__c,
        'Stepped back'
      );

      Id catchUp = BillingService.billDuePeriods(e.Id, start.addMonths(5));
      Student_Invoice__c inv = invoice(catchUp);
      Assert.areEqual(
        3 * 2360,
        inv.Total__c,
        'Three months up to the end date'
      );
      Assert.areEqual(
        BillingService.periodLabel(start.addMonths(1)) +
          ' - ' +
          BillingService.periodLabel(start.addMonths(3)),
        inv.Billing_Period__c,
        'Range label'
      );
      line = monthlyLine(e.Id);
      Assert.areEqual(4, line.Periods_Billed__c, 'Four periods');
      Assert.isTrue(line.Invoiced__c, 'Fully billed once past the end date');
      Invoice_Line__c last = [
        SELECT Period_End__c
        FROM Invoice_Line__c
        WHERE Student_Invoice__c = :catchUp
        ORDER BY Period_Start__c DESC
        LIMIT 1
      ];
      Assert.isTrue(
        last.Period_End__c <= e.EndDate,
        'Last period ends with the class'
      );

      // A cancelled first invoice releases the whole schedule.
      BillingService.cancel(catchUp, 'Re-bill');
      Assert.areEqual(1, monthlyLine(e.Id).Periods_Billed__c, 'Back to one');
      Assert.areEqual(
        new List<Date>{ start, start.addMonths(1) },
        BillingService.duePeriods(
          new Enrolment_Fee_Line__c(),
          new CourseOfferingParticipant(StartDate = start, EndDate = e.EndDate),
          start.addMonths(1)
        ),
        'A first invoice catches up on periods already started'
      );
      Assert.isTrue(
        KemJobs.jobFor('KEM Recurring Billing') instanceof RecurringBillingJob,
        'Job registered'
      );
    }
  }

  @IsTest
  static void instalmentPlanSettlesInOrder() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Id invoiceId = BillingService.createInvoice(e.Id, true);
      Date originalDue = invoice(invoiceId).Due_Date__c;
      BillingService.PlanRequest plan = new BillingService.PlanRequest();
      plan.invoiceId = invoiceId;
      plan.count = 3;
      plan.firstDueDate = Date.today().addDays(5);
      plan.intervalMonths = 1;

      List<BillingService.PlannedInstalment> preview = BillingController.previewInstalmentPlan(
        plan
      );
      Assert.areEqual(3, preview.size(), 'Three instalments');
      Assert.areEqual(1180, preview[0].amount, 'Equal split');
      Assert.areEqual(
        Date.today().addDays(5).addMonths(2),
        preview[2].dueDate,
        'Monthly'
      );

      BillingController.createInstalmentPlan(plan);
      Student_Invoice__c inv = invoice(invoiceId);
      Assert.areEqual(3, inv.Instalment_Count__c, 'Plan saved');
      Assert.areEqual(originalDue, inv.Original_Due_Date__c, 'Original kept');
      Assert.areEqual(
        Date.today().addDays(5),
        inv.Due_Date__c,
        'First instalment due'
      );
      try {
        BillingService.createPlan(plan);
        Assert.fail('One plan per invoice');
      } catch (AppException ex) {
        Assert.isTrue(ex.getMessage().contains('already'), ex.getMessage());
      }

      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoiceId;
      payment.amount = 1500;
      payment.method = 'Cash';
      BillingService.recordPayment(payment);
      List<Instalment__c> rows = [
        SELECT Status__c, Amount_Paid__c, Due_Date__c
        FROM Instalment__c
        WHERE Student_Invoice__c = :invoiceId
        ORDER BY Sequence__c
      ];
      Assert.areEqual('Paid', rows[0].Status__c, 'First settled');
      Assert.areEqual('Partially Paid', rows[1].Status__c, 'Second part paid');
      Assert.areEqual(320, rows[1].Amount_Paid__c, 'Remainder applied');
      Assert.areEqual('Due', rows[2].Status__c, 'Third due');
      Assert.areEqual(
        rows[1].Due_Date__c,
        invoice(invoiceId).Due_Date__c,
        'Due date moves on'
      );
      Assert.areEqual(
        3,
        BillingController.getInvoice(invoiceId).instalments.size(),
        'Shown on the invoice'
      );

      BillingController.removeInstalmentPlan(invoiceId);
      inv = invoice(invoiceId);
      Assert.areEqual(0, inv.Instalment_Count__c, 'Plan removed');
      Assert.areEqual(originalDue, inv.Due_Date__c, 'Due date restored');
    }
  }

  @IsTest
  static void planValidation() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Id draft = BillingService.createInvoice(e.Id, false);
      BillingService.PlanRequest plan = new BillingService.PlanRequest();
      plan.invoiceId = draft;
      plan.count = 3;
      plan.firstDueDate = Date.today();
      Integer failures = 0;
      List<String> expected = new List<String>{
        'Only issued',
        'between 2 and 12',
        '1 to 6 months',
        'due date',
        'before the invoice date',
        'no instalment plan'
      };
      for (Integer i = 0; i < expected.size(); i++) {
        try {
          switch on i {
            when 0 {
              BillingService.createPlan(plan);
            }
            when 1 {
              BillingService.issue(draft);
              plan.count = 1;
              BillingService.previewPlan(plan);
            }
            when 2 {
              plan.count = 2;
              plan.intervalMonths = 7;
              BillingService.previewPlan(plan);
            }
            when 3 {
              plan.intervalMonths = 1;
              plan.firstDueDate = null;
              BillingService.previewPlan(plan);
            }
            when 4 {
              plan.firstDueDate = Date.today().addDays(-1);
              BillingService.previewPlan(plan);
            }
            when 5 {
              BillingService.removePlan(draft);
            }
          }
        } catch (AppException ex) {
          Assert.isTrue(ex.getMessage().contains(expected[i]), ex.getMessage());
          failures++;
        }
      }
      Assert.areEqual(expected.size(), failures, 'Every rule enforced');
      Integer auraFailures = 0;
      for (Integer i = 0; i < 3; i++) {
        try {
          switch on i {
            when 0 {
              BillingController.previewInstalmentPlan(null);
            }
            when 1 {
              BillingController.createInstalmentPlan(null);
            }
            when 2 {
              BillingController.removeInstalmentPlan(
                TestUtil.fakeId(Student_Invoice__c.SObjectType)
              );
            }
          }
        } catch (AuraHandledException ex) {
          auraFailures++;
        }
      }
      Assert.areEqual(3, auraFailures, 'Controller reports friendly errors');
    }
  }
}
