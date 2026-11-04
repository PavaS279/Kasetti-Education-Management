@IsTest
private class PublicEnquiryControllerTest {
  private static PublicEnquiryController.SubmissionRequest validRequest(
    Branch__c branch,
    LearningCourse course
  ) {
    PublicEnquiryController.SubmissionRequest request = new PublicEnquiryController.SubmissionRequest();
    request.submissionId = 'portal-12345678-1234-1234-1234-123456789012';
    request.formStartedAt = DateTime.now().getTime() - 5000;
    request.firstName = 'Ananya';
    request.lastName = 'Sharma';
    request.birthdate = Date.today().addYears(-10);
    request.guardianFirstName = 'Rohit';
    request.guardianLastName = 'Sharma';
    request.guardianRelationship = 'Father';
    request.guardianEmail = 'rohit@example.com';
    request.guardianPhone = '+91 99000 01111';
    request.branchCode = branch.Branch_Code__c;
    request.courseExternalId = course.External_ID__c;
    request.deliveryMode = 'Classroom';
    request.referralCode = 'FAMILY-123';
    request.message = 'Please share the next available batch.';
    request.privacyConsent = true;
    return request;
  }

  @IsTest
  static void returnsOnlyActiveReferenceData() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c activeBranch = TestDataFactory.createBranch();
      Branch__c inactiveBranch = TestDataFactory.createBranch();
      inactiveBranch.Active__c = false;
      update inactiveBranch;
      LearningCourse course = TestDataFactory.createCourse('Public course');

      Test.startTest();
      PublicEnquiryController.FormData data = PublicEnquiryController.getFormData();
      Test.stopTest();

      Set<String> branchValues = new Set<String>();
      for (PublicEnquiryController.SelectOption option : data.branches) {
        branchValues.add(option.value);
      }
      Assert.isTrue(branchValues.contains(activeBranch.Branch_Code__c));
      Assert.isFalse(branchValues.contains(inactiveBranch.Branch_Code__c));
      Assert.isTrue(data.courses.size() > 0, 'Active courses are available');
      Assert.areEqual(6, data.relationships.size());
      Assert.areEqual(3, data.deliveryModes.size());
      Assert.isNotNull(course.Id);
    }
  }

  @IsTest
  static void createsAnIdempotentWebsiteEnquiry() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Public robotics');
      PublicEnquiryController.SubmissionRequest request = validRequest(
        branch,
        course
      );

      Test.startTest();
      PublicEnquiryController.SubmissionResult first = PublicEnquiryController.save(
        request
      );
      PublicEnquiryController.SubmissionResult repeat = PublicEnquiryController.save(
        request
      );
      Test.stopTest();

      Assert.isTrue(first.accepted);
      Assert.areEqual(first.reference, repeat.reference);
      List<Lead> enquiries = [
        SELECT
          Branch__c,
          Interested_Course__c,
          Enquiry_Channel__c,
          Guardian_Email__c
        FROM Lead
        WHERE Submission_Id__c = :request.submissionId
      ];
      Assert.areEqual(
        1,
        enquiries.size(),
        'Replay does not create a duplicate'
      );
      Assert.areEqual(branch.Id, enquiries[0].Branch__c);
      Assert.areEqual(course.Id, enquiries[0].Interested_Course__c);
      Assert.areEqual('Website', enquiries[0].Enquiry_Channel__c);
      Assert.areEqual('rohit@example.com', enquiries[0].Guardian_Email__c);
    }
  }

  @IsTest
  static void rejectsUntrustedOrIncompleteSubmissions() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Public maths');
      PublicEnquiryController.SubmissionRequest request = validRequest(
        branch,
        course
      );

      request.website = 'spam.example';
      assertRejected(request, 'Honeypot is enforced');
      request.website = null;
      request.privacyConsent = false;
      assertRejected(request, 'Consent is required');
      request.privacyConsent = true;
      request.guardianEmail = null;
      request.guardianPhone = null;
      assertRejected(request, 'At least one contact method is required');
      request.guardianEmail = 'not-an-email';
      assertRejected(request, 'Email format is checked');
      request.guardianEmail = 'rohit@example.com';
      request.formStartedAt = DateTime.now().getTime();
      assertRejected(request, 'Automated instant submissions are rejected');
    }
  }

  private static void assertRejected(
    PublicEnquiryController.SubmissionRequest request,
    String message
  ) {
    try {
      PublicEnquiryController.save(request);
      Assert.fail(message);
    } catch (AppException expected) {
      Assert.isNotNull(expected.getMessage(), message);
    }
  }
}
