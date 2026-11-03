/**
 * The simple college journey end to end: public enquiry with declared marks →
 * desk converts it into a college admission (marks confirmed, student reused)
 * → document verification is the desk's permission and stage-bound → the
 * admission letter and confirmation letter → a payment cannot be confirmed by
 * direct edit.
 */
@IsTest
private class CollegeEnquiryFlowTest {
  @TestSetup
  static void setup() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(5, 7);
    System.runAs(fixture.dean) {
      Admission_Rule__c rule = new Admission_Rule__c(
        Branch__c = fixture.branch.Id,
        Academic_Year__c = '2026-27',
        Entry_Route__c = 'Regular',
        Status__c = 'Draft',
        Entry_Year_Of_Study__c = 1,
        Qualifying_Level__c = 'SSLC',
        Min_Percentage__c = 60,
        Entrance_Required__c = false,
        Interview_Required__c = true
      );
      insert rule;
      AdmissionRuleService.activate(rule.Id);
      insert new Admission_Document_Rule__c(
        Academic_Year__c = '2026-27',
        Document_Type__c = 'SSLC_Marks',
        Label__c = 'SSLC marks card',
        Required__c = true,
        Sensitive_Class__c = 'Academic',
        Retain_File__c = true,
        Retention_Days__c = 365,
        Active__c = true
      );
    }
  }

  private static User desk() {
    User desk = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Admissions_Counsellor',
        'KEM_Admissions_Counsellor_Edu',
        'KEM_College_Admissions'
      }
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new GroupMember(
        GroupId = [
          SELECT Id
          FROM Group
          WHERE DeveloperName = 'KEM_College_Admissions_Team'
        ]
        .Id,
        UserOrGroupId = desk.Id
      );
    }
    return desk;
  }

  private static PublicEnquiryController.SubmissionRequest collegeRequest(
    Decimal sslc
  ) {
    Campus_Branch__c intake = [
      SELECT Id, Campus__r.Branch_Code__c, Branch__r.External_ID__c
      FROM Campus_Branch__c
      LIMIT 1
    ];
    PublicEnquiryController.SubmissionRequest request = new PublicEnquiryController.SubmissionRequest();
    request.submissionId =
      'portal-' +
      TestDataFactory.unique('college-enquiry-0000')
        .replaceAll('[^A-Za-z0-9-]', '-')
        .left(60);
    request.formStartedAt = DateTime.now().getTime() - 5000;
    request.firstName = 'Ravi';
    request.lastName = TestDataFactory.unique('Kumar');
    request.phone = '9876543210';
    request.privacyConsent = true;
    request.branchCode = intake.Campus__r.Branch_Code__c;
    request.courseExternalId = intake.Branch__r.External_ID__c;
    request.campusBranchId = intake.Id;
    request.entryRoute = 'Regular';
    CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
    q.level = 'SSLC';
    q.percentage = sslc;
    request.qualifications = new List<CollegeAdmissionController.Qualification>{
      q
    };
    return request;
  }

  @IsTest
  static void collegeEnquiryStoresTheDeclarationAndRejectsAMismatchedIntake() {
    PublicEnquiryController.SubmissionRequest request = collegeRequest(72);
    Test.startTest();
    PublicEnquiryController.save(request);
    PublicEnquiryController.SubmissionRequest wrong = collegeRequest(72);
    wrong.courseExternalId = null;
    try {
      PublicEnquiryController.save(wrong);
      Assert.fail('The intake must match the chosen campus and branch.');
    } catch (AppException expected) {
      Assert.isTrue(expected.getMessage().contains('programme'));
    }
    PublicEnquiryController.SubmissionRequest badMarks = collegeRequest(140);
    try {
      PublicEnquiryController.save(badMarks);
      Assert.fail('Marks above 100 are refused.');
    } catch (AppException expected) {
      Assert.isTrue(expected.getMessage().contains('marks'));
    }
    Test.stopTest();

    Lead enquiry = [
      SELECT Campus_Branch__c, Entry_Route__c, Declared_Marks__c
      FROM Lead
      WHERE Submission_Id__c = :request.submissionId
    ];
    Assert.areEqual(request.campusBranchId, enquiry.Campus_Branch__c);
    Assert.areEqual('Regular', enquiry.Entry_Route__c);
    Assert.isTrue(enquiry.Declared_Marks__c.contains('"percentage":72'));
  }

  @IsTest
  static void deskConvertsTheEnquiryIntoACollegeAdmissionWithoutRetyping() {
    PublicEnquiryController.SubmissionRequest request = collegeRequest(72);
    PublicEnquiryController.save(request);
    Lead enquiry = [
      SELECT Id
      FROM Lead
      WHERE Submission_Id__c = :request.submissionId
    ];
    User desk = desk();
    update new Lead(Id = enquiry.Id, OwnerId = desk.Id);
    MessageService.disabled = true;

    Test.startTest();
    EnquiryConversionService.ConversionResult result;
    System.runAs(desk) {
      EnquiryConversionService.ConversionPreview preview = EnquiryConversionService.preview(
        enquiry.Id
      );
      Assert.isNotNull(preview.college, 'Recognised as a college enquiry');
      Assert.isTrue(preview.college.canConvert);
      Assert.areEqual(72, preview.college.qualifications[0].percentage);

      EnquiryConversionService.ConversionRequest convert = new EnquiryConversionService.ConversionRequest();
      convert.leadId = enquiry.Id;
      try {
        EnquiryConversionService.convert(convert);
        Assert.fail(
          'The desk confirms the marks against the marks card first.'
        );
      } catch (AppException expected) {
        Assert.isTrue(expected.getMessage().contains('marks card'));
      }
      // The desk corrects a typo seen on the marks card while confirming.
      preview.college.qualifications[0].percentage = 74;
      convert.qualifications = preview.college.qualifications;
      convert.marksConfirmed = true;
      result = EnquiryConversionService.convert(convert);
    }
    Test.stopTest();

    IndividualApplication admission = [
      SELECT
        College_Mode__c,
        College_Stage__c,
        Campus_Branch__c,
        Entry_Route__c,
        Source_Enquiry__c,
        Privacy_Consent__c,
        Eligibility_Status__c,
        AccountId
      FROM IndividualApplication
      WHERE Id = :result.applicationId
    ];
    Assert.isTrue(admission.College_Mode__c);
    Assert.areEqual('Processing', admission.College_Stage__c);
    Assert.areEqual(request.campusBranchId, admission.Campus_Branch__c);
    Assert.areEqual('Regular', admission.Entry_Route__c);
    Assert.areEqual(enquiry.Id, admission.Source_Enquiry__c);
    Assert.isTrue(admission.Privacy_Consent__c, 'Consent from the website');
    Assert.areEqual(result.learnerId, admission.AccountId);
    Academic_Qualification__c sslc = [
      SELECT Percentage__c, Verified__c, Verified_By__c
      FROM Academic_Qualification__c
      WHERE Student__c = :result.learnerId
    ];
    Assert.areEqual(74, sslc.Percentage__c, 'The corrected value is kept');
    Assert.isTrue(sslc.Verified__c);
    Assert.areEqual(desk.Id, sslc.Verified_By__c);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Account WHERE LastName = :request.lastName],
      'One student record'
    );
    Assert.isTrue(
      [SELECT IsConverted FROM Lead WHERE Id = :enquiry.Id].IsConverted
    );
  }

  @IsTest
  static void walkInOfAnExistingStudentReusesTheRecord() {
    Campus_Branch__c intake = [SELECT Id FROM Campus_Branch__c LIMIT 1];
    Account existing = PersonAccountService.buildPerson(
      'Pooja',
      TestDataFactory.unique('Nayak'),
      'pooja.nayak@example.com',
      null,
      [SELECT Campus__c FROM Campus_Branch__c LIMIT 1].Campus__c,
      'Learner'
    );
    insert existing;
    User desk = desk();
    MessageService.disabled = true;
    Test.startTest();
    System.runAs(desk) {
      CollegeAdmissionController.NewAdmission walkIn = new CollegeAdmissionController.NewAdmission();
      walkIn.firstName = 'Pooja';
      walkIn.lastName = [SELECT LastName FROM Account WHERE Id = :existing.Id]
      .LastName;
      walkIn.email = 'pooja.nayak@example.com';
      walkIn.campusBranchId = intake.Id;
      walkIn.entryRoute = 'Regular';
      CollegeAdmissionController.Qualification q = new CollegeAdmissionController.Qualification();
      q.level = 'SSLC';
      q.percentage = 80;
      walkIn.qualifications = new List<CollegeAdmissionController.Qualification>{
        q
      };
      Id admissionId = CollegeAdmissionService.create(walkIn);
      Assert.areEqual(
        existing.Id,
        [SELECT AccountId FROM IndividualApplication WHERE Id = :admissionId]
        .AccountId,
        'The student on file is reused'
      );
      try {
        CollegeAdmissionService.create(walkIn);
        Assert.fail(
          'A second open admission for the same programme is refused.'
        );
      } catch (AppException expected) {
        Assert.isTrue(expected.getMessage().contains('open admission'));
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void onlyTheDeskVerifiesDocumentsAndOnlyBeforeTheInterview() {
    IndividualApplication admission = [
      SELECT Id
      FROM IndividualApplication
      WHERE College_Mode__c = TRUE
      LIMIT 1
    ];
    CollegeDocumentService.createChecklists(new Set<Id>{ admission.Id });
    update new IndividualApplication(
      Id = admission.Id,
      Privacy_Consent__c = true
    );
    DocumentChecklistItem item = [
      SELECT Id
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :admission.Id
      LIMIT 1
    ];
    User finance = TestDataFactory.createUserWithLicense(
      new List<String>{ 'KEM_Finance', 'KEM_Finance_Edu' }
    );
    Test.startTest();
    System.runAs(finance) {
      try {
        CollegeDocumentService.verify(item.Id, null);
        Assert.fail('Finance cannot verify admission documents.');
      } catch (AppException expected) {
        Assert.isTrue(expected.getMessage().contains('permission'));
      }
    }
    // The fixture admission is already at Ready For Decision (interviewed).
    User dean = [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = 'KEM_College_Dean'
        )
        AND IsActive = TRUE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    System.runAs(dean) {
      try {
        CollegeDocumentService.verify(item.Id, null);
        Assert.fail('Documents are verified before the interview only.');
      } catch (AppException expected) {
        Assert.isTrue(expected.getMessage().contains('before the Dean'));
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void admitIssuesTheAdmissionLetterAndFeeIssuesTheConfirmation() {
    User dean = [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = 'KEM_College_Dean'
        )
        AND IsActive = TRUE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    IndividualApplication admission = [
      SELECT Id
      FROM IndividualApplication
      WHERE College_Mode__c = TRUE AND College_Stage__c = 'Ready For Decision'
      LIMIT 1
    ];
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Test.startTest();
    System.runAs(dean) {
      Id enrolmentId = InterviewService.admit(admission.Id);
      Assert.areEqual(
        DocumentService.COLLEGE_ADMISSION_LETTER,
        DocumentService.kindFor(admission.Id)
      );
      Id letter = DocumentService.generate(
        admission.Id,
        DocumentService.COLLEGE_ADMISSION_LETTER
      );
      Assert.isNotNull(letter);
      try {
        DocumentService.generate(
          admission.Id,
          DocumentService.COLLEGE_CONFIRMATION_LETTER
        );
        Assert.fail('No confirmation before the fee is received.');
      } catch (AppException expected) {
        Assert.isTrue(expected.getMessage().contains('fee is received'));
      }
      Student_Invoice__c invoice = CollegeTestFactory.invoiceOf(enrolmentId);
      CollegeTestFactory.pay(invoice.Id, invoice.Total__c, 'Online Gateway');
      Assert.areEqual(
        DocumentService.COLLEGE_CONFIRMATION_LETTER,
        DocumentService.kindFor(admission.Id)
      );
      Id confirmation = DocumentService.generate(
        admission.Id,
        DocumentService.COLLEGE_CONFIRMATION_LETTER
      );
      Assert.areNotEqual(letter, confirmation);
      String title = [
        SELECT Title
        FROM ContentDocument
        WHERE Id = :confirmation
      ]
      .Title;
      Assert.isTrue(
        title.contains(
          [
            SELECT Roll_Number__c
            FROM Programme_Enrolment__c
            WHERE Id = :enrolmentId
          ]
          .Roll_Number__c
        ),
        'The confirmation names the roll number'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void aPendingDraftCannotBeConfirmedByDirectEdit() {
    User dean = [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = 'KEM_College_Dean'
        )
        AND IsActive = TRUE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    IndividualApplication admission = [
      SELECT Id
      FROM IndividualApplication
      WHERE College_Mode__c = TRUE AND College_Stage__c = 'Ready For Decision'
      LIMIT 1
    ];
    MessageService.disabled = true;
    DocumentService.suppressJobs = true;
    Test.startTest();
    System.runAs(dean) {
      Id enrolmentId = InterviewService.admit(admission.Id);
      Student_Invoice__c invoice = CollegeTestFactory.invoiceOf(enrolmentId);
      Id paymentId = CollegeTestFactory.pay(
          invoice.Id,
          invoice.Total__c,
          'Demand Draft'
        )
        .paymentId;
      Database.SaveResult direct = Database.update(
        new Student_Payment__c(Id = paymentId, Status__c = 'Confirmed'),
        false
      );
      Assert.isFalse(direct.isSuccess(), 'Direct confirmation is refused');
      Assert.isTrue(
        direct.getErrors()[0].getMessage().contains('Finance Desk')
      );
      BillingService.confirmPayment(paymentId);
      Assert.areEqual(
        'Enrolled',
        [SELECT Status__c FROM Programme_Enrolment__c WHERE Id = :enrolmentId]
        .Status__c,
        'The Finance Desk path confirms and releases the roll number'
      );
    }
    Test.stopTest();
  }
}
