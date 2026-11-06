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
    System.runAs(new User(Id = UserInfo.getUserId())) {
      // The college invoice sharing rule reaches the admissions team group.
      insert new GroupMember(
        GroupId = [
          SELECT Id
          FROM Group
          WHERE DeveloperName = 'KEM_College_Admissions_Team'
        ]
        .Id,
        UserOrGroupId = u.Id
      );
    }
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
    // The counsellor joins the team first, so the invoice is shared on creation.
    User desk = counsellor(f.campus.Id);
    Student_Invoice__c invoice = admitted(f);
    // In the org the college-invoice sharing rule gives the team read access;
    // tests do not see group-based rule shares, so share it directly.
    insert new Student_Invoice__Share(
      ParentId = invoice.Id,
      UserOrGroupId = desk.Id,
      AccessLevel = 'Read',
      RowCause = 'Manual'
    );
    Test.startTest();
    System.runAs(desk) {
      BillingService.FinanceDesk view = BillingService.financeDesk();
      Assert.isTrue(view.collegeOnly, 'Counsellor sees the college desk');
      Assert.isTrue(view.canCollect);
      Assert.isFalse(view.canManage);
      Assert.areEqual(1, view.collegeInvoices.size());
      Assert.isTrue(view.outstanding > 0);
      Assert.isTrue(BillingService.canCollectOn(invoice.Id));

      BillingService.PaymentResult paid = CollegeTestFactory.pay(
        invoice.Id,
        invoice.Total__c,
        'Demand Draft'
      );
      Assert.areEqual(1, BillingService.financeDesk().pending.size());
      BillingService.PaymentResult bounced = CollegeTestFactory.pay(
        invoice.Id,
        1000,
        'Cheque'
      );
      BillingService.failPayment(bounced.paymentId, 'Cheque bounced');
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
