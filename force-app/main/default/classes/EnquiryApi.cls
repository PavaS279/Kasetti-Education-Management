/**
 * REST endpoint for website and channel enquiries.
 *
 * POST /services/apexrest/kem/v1/enquiries
 * {
 *   "submissionId": "web-2026-000123",      // idempotency key (required)
 *   "branchCode": "BLR-01", "firstName": "Asha", "lastName": "Rao",
 *   "email": "asha@example.com", "phone": "+91...", "courseExternalId": "MATH-101",
 *   "channel": "Website", "deliveryMode": "Online", "message": "...",
 *   "guardian": { "firstName": "...", "lastName": "...", "email": "...", "phone": "...", "relationship": "Mother" }
 * }
 * Repeating a submissionId updates the same enquiry (HTTP 200) instead of
 * creating a duplicate (HTTP 201 on first create).
 */
@RestResource(urlMapping='/kem/v1/enquiries')
global with sharing class EnquiryApi {
  global class GuardianPayload {
    public String firstName;
    public String lastName;
    public String email;
    public String phone;
    public String relationship;
  }

  global class EnquiryPayload {
    public String submissionId;
    public String branchCode;
    public String firstName;
    public String lastName;
    public String email;
    public String phone;
    public String courseExternalId;
    public String channel;
    public String deliveryMode;
    public String message;
    public Date birthdate;
    public GuardianPayload guardian;
    /** Optional referral code of the family or alumnus who referred the enquirer (F4.11). */
    public String referralCode;
  }

  global class EnquiryResponse {
    public Id enquiryId;
    public Boolean created;
    public Boolean possibleDuplicate;
    public String error;
  }

  @HttpPost
  global static void submit() {
    RestResponse response = RestContext.response;
    response.addHeader('Content-Type', 'application/json');
    EnquiryResponse body = new EnquiryResponse();
    try {
      EnquiryPayload payload = (EnquiryPayload) JSON.deserialize(
        RestContext.request.requestBody.toString(),
        EnquiryPayload.class
      );
      validate(payload);
      Lead enquiry = toLead(payload);
      List<Lead> existing = [
        SELECT Id
        FROM Lead
        WHERE Submission_Id__c = :payload.submissionId
        WITH USER_MODE
        LIMIT 1
      ];
      body.created = existing.isEmpty();
      if (!body.created) {
        enquiry.Id = existing[0].Id;
      }
      Database.upsert(enquiry, AccessLevel.USER_MODE);
      body.enquiryId = enquiry.Id;
      body.possibleDuplicate = [
        SELECT Possible_Duplicate__c
        FROM Lead
        WHERE Id = :enquiry.Id
        WITH USER_MODE
      ]
      .Possible_Duplicate__c;
      response.statusCode = body.created ? 201 : 200;
    } catch (AppException e) {
      body.error = e.getMessage();
      response.statusCode = 400;
    } catch (JSONException e) {
      body.error = 'Malformed JSON: ' + e.getMessage();
      response.statusCode = 400;
    } catch (Exception e) {
      Logger.error('EnquiryApi.submit', e, null);
      body.error =
        'The enquiry could not be saved. Reference: ' +
        Request.getCurrent().getRequestId();
      response.statusCode = 500;
    }
    response.responseBody = Blob.valueOf(JSON.serialize(body, true));
  }

  private static void validate(EnquiryPayload payload) {
    if (payload == null || String.isBlank(payload.submissionId)) {
      throw new AppException('submissionId is required.');
    }
    if (String.isBlank(payload.lastName)) {
      throw new AppException('lastName is required.');
    }
    if (String.isBlank(payload.branchCode)) {
      throw new AppException('branchCode is required.');
    }
  }

  private static Lead toLead(EnquiryPayload payload) {
    List<Branch__c> branches = [
      SELECT Id
      FROM Branch__c
      WHERE Branch_Code__c = :payload.branchCode AND Active__c = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    if (branches.isEmpty()) {
      throw new AppException(
        'Unknown or inactive branchCode: ' + payload.branchCode
      );
    }
    Lead enquiry = new Lead(
      Submission_Id__c = payload.submissionId,
      Branch__c = branches[0].Id,
      FirstName = payload.firstName,
      LastName = payload.lastName,
      Email = payload.email,
      MobilePhone = payload.phone,
      Learner_Birthdate__c = payload.birthdate,
      Enquiry_Channel__c = String.isBlank(payload.channel)
        ? 'Website'
        : payload.channel,
      Preferred_Delivery_Mode__c = payload.deliveryMode,
      Description = payload.message,
      Referral_Code__c = payload.referralCode == null
        ? null
        : payload.referralCode.left(20),
      LeadSource = 'Web'
    );
    if (String.isNotBlank(payload.courseExternalId)) {
      List<LearningCourse> courses = [
        SELECT Id
        FROM LearningCourse
        WHERE External_ID__c = :payload.courseExternalId
        WITH USER_MODE
        LIMIT 1
      ];
      if (courses.isEmpty()) {
        throw new AppException(
          'Unknown courseExternalId: ' + payload.courseExternalId
        );
      }
      enquiry.Interested_Course__c = courses[0].Id;
    }
    if (payload.guardian != null) {
      enquiry.Guardian_First_Name__c = payload.guardian.firstName;
      enquiry.Guardian_Last_Name__c = payload.guardian.lastName;
      enquiry.Guardian_Email__c = payload.guardian.email;
      enquiry.Guardian_Phone__c = payload.guardian.phone;
      enquiry.Guardian_Relationship__c = payload.guardian.relationship;
    }
    return enquiry;
  }
}
