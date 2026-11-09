@IsTest
private class CollegeExceptionFlowTest {
  private static User counsellor(Id applicationId) {
    User u = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    // In the org the admissions-team sharing rule gives edit access.
    insert new IndividualApplicationShare(
      ParentId = applicationId,
      UserOrGroupId = u.Id,
      AccessLevel = 'Edit',
      RowCause = 'Manual'
    );
    return u;
  }

  private static void documentsVerified(Id applicationId, String eligibility) {
    update new IndividualApplication(
      Id = applicationId,
      College_Stage__c = 'Documents Verified',
      Eligibility_Status__c = eligibility,
      Interview_Date__c = null,
      Interviewer__c = null,
      Interview_Outcome__c = null
    );
  }

  private static IndividualApplication reload(Id applicationId) {
    return [
      SELECT
        College_Stage__c,
        Exception_Status__c,
        Exception_Requested_By__c,
        Exception_Decided_By__c,
        Decision__c
      FROM IndividualApplication
      WHERE Id = :applicationId
    ];
  }

  private static String refusal(Id applicationId) {
    try {
      InterviewService.admit(applicationId);
      return null;
    } catch (AppException e) {
      return e.getMessage();
    }
  }

  @IsTest
  static void counsellorAdmitsAnEligibleApplicantWithoutTheDean() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    documentsVerified(f.admission.Id, 'Eligible');
    User desk = counsellor(f.admission.Id);
    Test.startTest();
    System.runAs(desk) {
      CollegeAdmissionController.Admission view = CollegeAdmissionController.getAdmission(
        f.admission.Id
      );
      Assert.isTrue(view.admissible, 'Eligible: the counsellor can admit');
      Assert.isFalse(view.needsException);
      InterviewService.admit(f.admission.Id);
    }
    Test.stopTest();
    Assert.areEqual('Fee Pending', reload(f.admission.Id).College_Stage__c);
  }

  @IsTest
  static void anApplicantWhoMissesTheCriteriaNeedsTheDean() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    documentsVerified(f.admission.Id, 'Not Eligible');
    User desk = counsellor(f.admission.Id);
    Test.startTest();
    System.runAs(desk) {
      Assert.isNotNull(refusal(f.admission.Id), 'Not eligible: no admit');
      Assert.isTrue(
        CollegeAdmissionController.getAdmission(f.admission.Id).needsException
      );
      try {
        InterviewService.requestException(f.admission.Id, ' ');
        Assert.fail('A reason is required');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('why'), e.getMessage());
      }
      CollegeAdmissionController.requestException(
        f.admission.Id,
        'PUC 58%, cut-off 60%; state-level sports certificate attached.'
      );
      Assert.isTrue(
        refusal(f.admission.Id).contains('not yet decided'),
        'Waits for the Dean'
      );
    }
    IndividualApplication waiting = reload(f.admission.Id);
    Assert.areEqual(InterviewService.AWAITING_DEAN, waiting.College_Stage__c);
    Assert.areEqual('Requested', waiting.Exception_Status__c);
    Assert.areEqual(desk.Id, waiting.Exception_Requested_By__c);

    System.runAs(f.dean) {
      CollegeAdmissionController.approveException(
        f.admission.Id,
        'Approved on the sports certificate.'
      );
    }
    IndividualApplication approved = reload(f.admission.Id);
    Assert.areEqual('Documents Verified', approved.College_Stage__c);
    Assert.areEqual('Approved', approved.Exception_Status__c);
    Assert.areEqual(f.dean.Id, approved.Exception_Decided_By__c);
    System.runAs(desk) {
      Assert.isTrue(
        CollegeAdmissionController.getAdmission(f.admission.Id).admissible
      );
      CollegeAdmissionController.admit(f.admission.Id);
    }
    Test.stopTest();
    Assert.areEqual('Fee Pending', reload(f.admission.Id).College_Stage__c);
  }

  @IsTest
  static void theDeanCanInterviewAndDecline() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    documentsVerified(f.admission.Id, 'Not Eligible');
    User desk = counsellor(f.admission.Id);
    System.runAs(desk) {
      InterviewService.requestException(f.admission.Id, 'Management request');
    }
    Test.startTest();
    System.runAs(f.dean) {
      try {
        CollegeAdmissionController.declineException(f.admission.Id, '');
        Assert.fail('A reason is required');
      } catch (AuraHandledException e) {
        Assert.isTrue(true);
      }
      CollegeAdmissionController.scheduleInterview(
        f.admission.Id,
        System.now().addMinutes(-5)
      );
      CollegeAdmissionController.recordOutcome(
        f.admission.Id,
        'Reject',
        'Not suitable for this branch.'
      );
    }
    Test.stopTest();
    IndividualApplication closed = reload(f.admission.Id);
    Assert.areEqual('Application Decision', closed.College_Stage__c);
    Assert.areEqual('Declined', closed.Exception_Status__c);
    Assert.areEqual('Reject', closed.Decision__c);
  }

  @IsTest
  static void theDeanApprovesAfterAPassedInterview() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    documentsVerified(f.admission.Id, 'Not Eligible');
    User desk = counsellor(f.admission.Id);
    System.runAs(desk) {
      InterviewService.requestException(f.admission.Id, 'Merit in practicals');
    }
    Test.startTest();
    System.runAs(f.dean) {
      InterviewService.schedule(
        f.admission.Id,
        System.now().addMinutes(-5),
        f.dean.Id
      );
      InterviewService.recordOutcome(f.admission.Id, 'Pass', 'Strong viva.');
    }
    Test.stopTest();
    IndividualApplication approved = reload(f.admission.Id);
    Assert.areEqual('Documents Verified', approved.College_Stage__c);
    Assert.areEqual('Approved', approved.Exception_Status__c);
  }

  @IsTest
  static void anEligibleApplicantCannotBeSentToTheDean() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    documentsVerified(f.admission.Id, 'Eligible');
    User desk = counsellor(f.admission.Id);
    System.runAs(desk) {
      try {
        InterviewService.requestException(f.admission.Id, 'Just in case');
        Assert.fail('Eligible applicants are admitted by the counsellor');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('meets the criteria'));
      }
    }
  }

  @IsTest
  static void aReasonTypedAtCreationGoesToTheDeanAndTheStudentIsAdmitted() {
    CollegeTestFactory.Fixture f = CollegeTestFactory.create(5, 7);
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    CollegeAdmissionController.NewAdmission request = new CollegeAdmissionController.NewAdmission();
    request.firstName = 'Kiran';
    request.lastName = TestDataFactory.uniqueName('Below');
    request.campusBranchId = f.intake.Id;
    request.entryRoute = 'Regular';
    CollegeAdmissionController.Qualification sslc = new CollegeAdmissionController.Qualification();
    sslc.level = 'SSLC';
    sslc.percentage = 55;
    request.qualifications = new List<CollegeAdmissionController.Qualification>{
      sslc
    };
    request.exceptionReason = '  State-level sports certificate attached.  ';
    Id applicationId;
    System.runAs(f.dean) {
      applicationId = CollegeAdmissionService.create(request, null);
    }
    Assert.areEqual(
      'State-level sports certificate attached.',
      [
        SELECT Exception_Reason__c
        FROM IndividualApplication
        WHERE Id = :applicationId
      ]
      .Exception_Reason__c,
      'The reason is kept for the request'
    );
    // Below the cut-off and not yet verified: the panel says the Dean is needed.
    update new IndividualApplication(
      Id = applicationId,
      College_Stage__c = 'Processing',
      Eligibility_Status__c = 'Not Eligible'
    );
    System.runAs(f.dean) {
      Assert.isTrue(
        CollegeAdmissionController.getAdmission(applicationId).needsDeanLater
      );
    }
    update new IndividualApplication(
      Id = applicationId,
      College_Stage__c = 'Documents Verified'
    );
    Test.startTest();
    System.runAs(f.dean) {
      // No reason now: the one typed at creation is sent.
      InterviewService.requestException(applicationId, null);
      Assert.areEqual(
        'Requested',
        [
          SELECT Exception_Status__c
          FROM IndividualApplication
          WHERE Id = :applicationId
        ]
        .Exception_Status__c
      );
      InterviewService.approveException(applicationId, 'Approved.');
      InterviewService.admit(applicationId);
    }
    Test.stopTest();
    Assert.areEqual(
      'Fee Pending',
      [
        SELECT College_Stage__c
        FROM IndividualApplication
        WHERE Id = :applicationId
      ]
      .College_Stage__c
    );
  }
}
