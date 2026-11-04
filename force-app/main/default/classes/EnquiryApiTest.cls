@IsTest
private class EnquiryApiTest {
  private static RestResponse post(Map<String, Object> body) {
    RestRequest request = new RestRequest();
    request.requestURI = '/services/apexrest/kem/v1/enquiries';
    request.httpMethod = 'POST';
    request.requestBody = Blob.valueOf(JSON.serialize(body));
    RestContext.request = request;
    RestContext.response = new RestResponse();
    EnquiryApi.submit();
    return RestContext.response;
  }

  private static Map<String, Object> payload(
    Branch__c branch,
    String courseKey
  ) {
    return new Map<String, Object>{
      'submissionId' => 'web-0001',
      'branchCode' => branch.Branch_Code__c,
      'firstName' => 'Meera',
      'lastName' => 'Iyer',
      'email' => 'meera.iyer@example.com',
      'phone' => '+919900001111',
      'courseExternalId' => courseKey,
      'deliveryMode' => 'Online',
      'guardian' => new Map<String, Object>{
        'firstName' => 'Lakshmi',
        'lastName' => 'Iyer',
        'relationship' => 'Mother'
      }
    };
  }

  @IsTest
  static void createsThenUpdatesIdempotently() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Physics');
      RestResponse first = post(payload(branch, course.External_ID__c));
      Assert.areEqual(201, first.statusCode, first.responseBody.toString());

      Map<String, Object> repeat = payload(branch, course.External_ID__c);
      repeat.put('firstName', 'Meera K');
      RestResponse second = post(repeat);
      Assert.areEqual(200, second.statusCode, second.responseBody.toString());

      List<Lead> leads = [
        SELECT
          FirstName,
          Interested_Course__c,
          Enquiry_Channel__c,
          Guardian_Last_Name__c
        FROM Lead
        WHERE Submission_Id__c = 'web-0001'
      ];
      Assert.areEqual(
        1,
        leads.size(),
        'Repeated submission does not duplicate the enquiry'
      );
      Assert.areEqual(
        'Meera K',
        leads[0].FirstName,
        'Repeat updates the enquiry'
      );
      Assert.areEqual(
        course.Id,
        leads[0].Interested_Course__c,
        'Course resolved by external ID'
      );
      Assert.areEqual(
        'Website',
        leads[0].Enquiry_Channel__c,
        'Channel defaults to Website'
      );
      Assert.areEqual(
        'Iyer',
        leads[0].Guardian_Last_Name__c,
        'Guardian captured'
      );
    }
  }

  @IsTest
  static void rejectsInvalidRequests() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Map<String, Object> noKey = payload(branch, null);
      noKey.remove('submissionId');
      Assert.areEqual(400, post(noKey).statusCode, 'submissionId required');

      Map<String, Object> badBranch = payload(branch, null);
      badBranch.put('branchCode', 'NOPE');
      Assert.areEqual(
        400,
        post(badBranch).statusCode,
        'Unknown branch rejected'
      );

      Map<String, Object> badCourse = payload(branch, 'NOPE');
      Assert.areEqual(
        400,
        post(badCourse).statusCode,
        'Unknown course rejected'
      );

      Map<String, Object> noName = payload(branch, null);
      noName.remove('lastName');
      Assert.areEqual(400, post(noName).statusCode, 'lastName required');

      RestRequest request = new RestRequest();
      request.requestBody = Blob.valueOf('{not json');
      RestContext.request = request;
      RestContext.response = new RestResponse();
      EnquiryApi.submit();
      Assert.areEqual(
        400,
        RestContext.response.statusCode,
        'Malformed JSON rejected'
      );

      Map<String, Object> noBranch = payload(branch, null);
      noBranch.remove('branchCode');
      Assert.areEqual(400, post(noBranch).statusCode, 'branchCode required');
    }
  }
}
