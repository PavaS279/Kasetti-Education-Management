@IsTest
private class CollegeFeeCollectionTest {
  private static User counsellor(Id campusId) {
    User u = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    if (campusId != null) {
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert new Branch_Staff__c(
          Branch__c = campusId,
          User__c = u.Id,
          Role__c = 'Admissions Counsellor',
          Active__c = true
        );
      }
    }
    return u;
  }

  private static Student_Invoice__c admitted(CollegeTestFactory.Fixture f) {
    Id enrolmentId;
    System.runAs(f.dean) {
      enrolmentId = InterviewService.admit(f.admission.Id);
    }
    return CollegeTestFactory.invoiceOf(enrolmentId);
  }

  @IsTest
  static void counsellorRecordsAndConfirmsAtTheirCampus() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Student_Invoice__c invoice = admitted(f);
    User desk = counsellor(f.campus.Id);
    Test.startTest();
    System.runAs(desk) {
      BillingService.FinanceDesk view = BillingService.financeDesk();
      Assert.isTrue(view.collegeOnly, 'Counsellor sees the college desk');
      Assert.isTrue(view.canCollect);
      Assert.isFalse(view.canManage);
      Assert.areEqual(1, view.collegeInvoices.size());
      Assert.isTrue(view.outstanding > 0);
      Assert.isTrue(BillingService.getInvoice(invoice.Id).canCollect);

      BillingService.PaymentResult paid = CollegeTestFactory.pay(
        invoice.Id,
        invoice.Total__c,
        'Demand Draft'
      );
      Assert.areEqual(1, BillingService.financeDesk().pending.size());
      BillingService.confirmPayment(paid.paymentId);
      try {
        BillingService.cancel(invoice.Id, 'Not allowed');
        Assert.fail('Cancelling stays with finance');
      } catch (Exception e) {
        Assert.isTrue(true);
      }
    }
    Test.stopTest();
    Assert.areEqual(
      'Paid',
      [SELECT Status__c FROM Student_Invoice__c WHERE Id = :invoice.Id]
      .Status__c
    );
  }

  @IsTest
  static void counsellorOfAnotherCampusIsRefused() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Student_Invoice__c invoice = admitted(f);
    User elsewhere = counsellor(null);
    System.runAs(elsewhere) {
      Assert.areEqual(0, BillingService.financeDesk().collegeInvoices.size());
      try {
        CollegeTestFactory.pay(invoice.Id, invoice.Total__c, 'Demand Draft');
        Assert.fail('Not their campus');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('your campuses'), e.getMessage());
      }
    }
  }
}
