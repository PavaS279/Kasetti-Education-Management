@IsTest
private class AnalyticsServiceTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'ANA-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Analytics Maths');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        4
      );
      List<Account> learners = new List<Account>();
      for (Integer i = 0; i < 2; i++) {
        learners.add(
          PersonAccountService.buildPerson(
            'Ana' + i,
            'Lytics' + Crypto.getRandomInteger(),
            null,
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      List<Id> enrolments = new List<Id>();
      for (Account learner : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learner.Id;
        request.offeringId = offering.Id;
        enrolments.add(EnrolmentService.enrol(request).enrolmentId);
      }
      Id invoiceId = BillingService.createInvoice(enrolments[0], true);
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoiceId;
      payment.amount = 590;
      payment.method = 'UPI';
      payment.confirmed = true;
      BillingService.recordPayment(payment);
      Database.update(
        new CourseOfferingParticipant(
          Id = enrolments[1],
          ParticipationStatus = 'Withdrew'
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  @IsTest
  static void dashboardAggregatesTheBranch() {
    Id branchId = [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'ANA-01'].Id;
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      AnalyticsService.Dashboard d = AnalyticsController.getDashboard(
        branchId,
        6
      );
      Test.stopTest();
      Assert.areEqual(6, d.months.size(), 'Six months');
      AnalyticsService.MonthPoint current = d.months[5];
      Assert.areEqual(1180, current.invoiced, 'Invoiced this month');
      Assert.areEqual(590, current.collected, 'Collected this month');
      Assert.areEqual(2, current.newEnrolments, 'New enrolments');
      Assert.areEqual(1, current.withdrawals, 'Withdrawal');
      Assert.areEqual(50.0, d.collectionRate, 'Collection rate');
      Assert.areEqual(6, d.cohorts.size(), 'Six cohorts');
      AnalyticsService.Cohort cohort = d.cohorts[5];
      Assert.areEqual(2, cohort.enrolled, 'Cohort size');
      Assert.areEqual(1, cohort.withdrawn, 'Withdrawn');
      Assert.areEqual(50.0, cohort.retention, 'Retention');
      Assert.areEqual(5, d.ageing.size(), 'Ageing buckets');
      Decimal outstanding = 0;
      for (AnalyticsService.AgeingBucket bucket : d.ageing) {
        outstanding += bucket.amount;
      }
      Assert.areEqual(590, outstanding, 'Outstanding balance');
      Assert.areEqual(1, d.courses.size(), 'Course row');
      Assert.areEqual('Analytics Maths', d.courses[0].course, 'Course');
      Assert.isTrue(
        d.showFinance && d.showEnrolments && d.showAttendance,
        'Sections'
      );
      Assert.isFalse(AnalyticsController.getBranches().isEmpty(), 'Branches');
    }
  }

  @IsTest
  static void teachersSeeNoFinance() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      AnalyticsService.Dashboard d = AnalyticsService.dashboard(null, null);
      Assert.areEqual(12, d.months.size(), 'Default twelve months');
      Assert.isFalse(d.showFinance, 'No finance for teachers');
    }
  }
}
