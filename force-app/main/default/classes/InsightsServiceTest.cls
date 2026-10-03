@IsTest
private class InsightsServiceTest {
  @IsTest
  static void administratorSeesEverySection() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(TestDataFactory.admin()) {
      TestDataFactory.createReferenceData();
      DocumentService.suppressJobs = true;
      Branch__c branch = TestDataFactory.createBranch();
      insert TestDataFactory.buildEnquiry(branch.Id);
      LearningCourse course = TestDataFactory.createCourse('Statistics');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-1)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        4
      );
      Account learner = PersonAccountService.buildPerson(
        'Ins',
        'Ight' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoiceId;
      payment.amount = 180;
      payment.method = 'Cash';
      BillingService.recordPayment(payment);

      Datetime laterToday = Datetime.newInstance(
        Date.today(),
        Time.newInstance(23, 0, 0, 0)
      );
      insert new Class_Session__c(
        Course_Offering__c = offering.Id,
        Teacher_User__c = teacher.Id,
        Start__c = laterToday,
        End__c = laterToday.addMinutes(30)
      );

      InsightsService.Insights insights = InsightsController.getInsights();
      Assert.isTrue(insights.showAdmissions, 'Admissions');
      Assert.isTrue(insights.openEnquiries >= 1, 'Open enquiry counted');
      Assert.isTrue(insights.newEnquiriesThisWeek >= 1, 'New this week');
      Assert.isTrue(insights.showClasses, 'Classes');
      Assert.isTrue(insights.seatCapacity >= 4, 'Capacity');
      Assert.isTrue(insights.seatsTaken >= 1, 'Seat taken');
      Assert.isTrue(insights.showAttendance, 'Attendance');
      Assert.isTrue(insights.showFinance, 'Finance');
      Assert.isTrue(insights.outstanding >= 1000, 'Outstanding 1180 - 180');
      Assert.isTrue(insights.collectedThisMonth >= 180, 'Collected');
      Assert.isFalse(insights.todaysSessions.isEmpty(), 'Today\'s session');
    }
    System.runAs(teacher) {
      InsightsService.Insights mine = InsightsService.load();
      Assert.isFalse(mine.showFinance, 'Teachers do not see receivables');
      Assert.isFalse(mine.showAdmissions, 'Teachers do not see the funnel');
      Assert.areEqual(1, mine.todaysSessions.size(), 'Their own session');
    }
  }

  @IsTest
  static void controllerReportsFailures() {
    InsightsService.simulateFailure = true;
    try {
      InsightsController.getInsights();
      Assert.fail('Expected a friendly error');
    } catch (AuraHandledException e) {
      Assert.isTrue(
        e.getMessage().contains('temporarily unavailable'),
        e.getMessage()
      );
    }
  }
}
