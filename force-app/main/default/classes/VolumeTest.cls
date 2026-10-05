/**
 * Volume and limit tests: bulk triggers and scheduled work at batch sizes,
 * with the governor limits they consume asserted so regressions show up
 * before they reach a busy centre.
 */
@IsTest
private class VolumeTest {
  private static final Integer VOLUME = 200;

  private class Family {
    Branch__c branch;
    Account learner;
    Id learnerContactId;
  }

  private static Family family() {
    Family f = new Family();
    f.branch = TestDataFactory.createBranch();
    f.learner = PersonAccountService.buildPerson(
      'Volume',
      'Learner' + Crypto.getRandomInteger(),
      'volume.learner@example.com',
      null,
      f.branch.Id,
      'Learner'
    );
    insert f.learner;
    f.learnerContactId = [
      SELECT PersonContactId
      FROM Account
      WHERE Id = :f.learner.Id
    ]
    .PersonContactId;
    return f;
  }

  /** Issued invoices due on the given date, with one line each. */
  private static List<Student_Invoice__c> invoices(
    Family f,
    Integer count,
    Date dueDate
  ) {
    List<Student_Invoice__c> rows = new List<Student_Invoice__c>();
    for (Integer i = 0; i < count; i++) {
      rows.add(
        new Student_Invoice__c(
          Name = 'VOL-' + String.valueOf(i).leftPad(6, '0'),
          Bill_To__c = f.learnerContactId,
          Learner__c = f.learnerContactId,
          Learner_Account__c = f.learner.Id,
          Branch__c = f.branch.Id,
          Status__c = 'Issued',
          Issue_Date__c = dueDate.addDays(-15),
          Due_Date__c = dueDate
        )
      );
    }
    Database.insert(rows, AccessLevel.SYSTEM_MODE);
    List<Invoice_Line__c> lines = new List<Invoice_Line__c>();
    for (Student_Invoice__c invoice : rows) {
      lines.add(
        new Invoice_Line__c(
          Student_Invoice__c = invoice.Id,
          Fee_Type__c = 'Tuition',
          Description__c = 'Tuition',
          Unit_Amount__c = 1000,
          Line_Total__c = 1000
        )
      );
    }
    Database.insert(lines, AccessLevel.SYSTEM_MODE);
    return rows;
  }

  @IsTest
  static void reminderBatchCoversEveryInvoiceDue() {
    System.runAs(TestDataFactory.admin()) {
      Family f = family();
      invoices(f, VOLUME, Date.today().addDays(3));
      Test.startTest();
      Id jobId = ReminderJob.run(Date.today());
      Test.stopTest();
      Assert.isNotNull(jobId, 'Batch started');
      Assert.areEqual(
        VOLUME,
        [
          SELECT COUNT()
          FROM Message__c
          WHERE Channel__c = 'Portal' AND Event__c = 'Invoice_Due_Soon'
        ],
        'One due-soon notice per invoice'
      );
    }
  }

  @IsTest
  static void remindersUseAFixedNumberOfQueries() {
    System.runAs(TestDataFactory.admin()) {
      Family f = family();
      Date today = Date.today();
      List<Student_Invoice__c> rows = invoices(f, VOLUME, today.addDays(-7));
      Set<Id> ids = new Map<Id, Student_Invoice__c>(rows).keySet();
      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      Integer dmlBefore = Limits.getDmlStatements();
      Integer created = MessageService.remindInvoices(ids, today);
      Integer queries = Limits.getQueries() - queriesBefore;
      Integer dml = Limits.getDmlStatements() - dmlBefore;
      Test.stopTest();
      Assert.isTrue(created >= VOLUME, 'Overdue reminders: ' + created);
      Assert.isTrue(queries <= 15, 'Queries for 200 invoices: ' + queries);
      Assert.isTrue(dml <= 5, 'DML statements for 200 invoices: ' + dml);
      Assert.areEqual(
        0,
        MessageService.remindInvoices(ids, today),
        'Running again sends nothing (dedup)'
      );
    }
  }

  @IsTest
  static void recurringBillingLeavesWorkForAFollowUpRun() {
    RecurringBillingJob job = new RecurringBillingJob(Date.today());
    RecurringBillingJob.queryLimitOverride = 0;
    job.execute(
      null,
      new List<CourseOfferingParticipant>{
        new CourseOfferingParticipant(),
        new CourseOfferingParticipant(),
        new CourseOfferingParticipant()
      }
    );
    Assert.areEqual(3, job.deferred, 'All left for the follow-up run');
    Assert.areEqual(0, job.invoiced, 'Nothing billed');
    job.finish(null);
    Assert.areEqual(
      5,
      RecurringBillingJob.batchSize(),
      'Small batches: about 20 queries per enrolment'
    );
  }

  @IsTest
  static void dispatchKeepsEmailQueuedWhenTheDailyLimitIsReached() {
    System.runAs(TestDataFactory.admin()) {
      Family f = family();
      Database.insert(
        new Message__c(
          Recipient__c = f.learnerContactId,
          Channel__c = 'Email',
          Status__c = 'Queued',
          Subject__c = 'Waiting for allowance',
          Body__c = 'x'
        ),
        AccessLevel.SYSTEM_MODE
      );
      AppSettings.overrides.put('Email_Delivery', 'Live');
      MessageService.emailCapacityOverride = 0;
      Test.startTest();
      Assert.areEqual(0, MessageService.dispatch(100), 'Nothing sent');
      Test.stopTest();
      Assert.areEqual(
        'Queued',
        [
          SELECT Status__c
          FROM Message__c
          WHERE Subject__c = 'Waiting for allowance'
        ]
        .Status__c,
        'Still queued for tomorrow, not failed'
      );
      Assert.isTrue(
        MessageService.emailCapacity() == 0,
        'Capacity override honoured'
      );
    }
  }

  @IsTest
  static void sessionTriggersHandle200Records() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Volume');
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        30
      );
      Datetime first = Datetime.newInstance(
        Date.today().addDays(1),
        Time.newInstance(9, 0, 0, 0)
      );
      List<Class_Session__c> sessions = new List<Class_Session__c>();
      for (Integer i = 0; i < VOLUME; i++) {
        sessions.add(
          new Class_Session__c(
            Course_Offering__c = offering.Id,
            Branch__c = branch.Id,
            Start__c = first.addDays(i),
            End__c = first.addDays(i).addHours(1)
          )
        );
      }
      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      insert sessions;
      for (Class_Session__c s : sessions) {
        s.Notes__c = 'Bring the workbook';
      }
      update sessions;
      Integer queries = Limits.getQueries() - queriesBefore;
      Test.stopTest();
      Assert.areEqual(
        VOLUME,
        [
          SELECT COUNT()
          FROM Class_Session__c
          WHERE Course_Offering__c = :offering.Id
        ],
        'All sessions saved'
      );
      Assert.isTrue(queries <= 20, 'Queries for 200 sessions: ' + queries);
    }
  }

  @IsTest
  static void enquiryTriggersHandle200Records() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      List<Lead> enquiries = new List<Lead>();
      for (Integer i = 0; i < VOLUME; i++) {
        enquiries.add(TestDataFactory.buildEnquiry(branch.Id));
      }
      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      insert enquiries;
      Integer queries = Limits.getQueries() - queriesBefore;
      Test.stopTest();
      Assert.areEqual(
        VOLUME,
        [SELECT COUNT() FROM Lead WHERE Branch__c = :branch.Id],
        'All enquiries saved'
      );
      Assert.isTrue(queries <= 30, 'Queries for 200 enquiries: ' + queries);
    }
  }

  @IsTest
  static void branchComparisonUsesAggregates() {
    System.runAs(TestDataFactory.admin()) {
      List<Branch__c> branches = new List<Branch__c>();
      for (Integer i = 0; i < 50; i++) {
        Branch__c b = TestDataFactory.buildBranch();
        b.Branch_Code__c = 'VOL-' + i;
        b.Invoice_Prefix__c = 'V' + i;
        branches.add(b);
      }
      insert branches;
      Test.startTest();
      Integer queriesBefore = Limits.getQueries();
      BranchTemplateService.Overview o = BranchTemplateService.overview();
      Integer queries = Limits.getQueries() - queriesBefore;
      Test.stopTest();
      Assert.areEqual(50, o.branches.size(), 'Every branch');
      Assert.isTrue(queries <= 10, 'Queries for 50 branches: ' + queries);
    }
  }
}
