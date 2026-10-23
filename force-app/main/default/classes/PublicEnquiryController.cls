/**
 * Deliberately narrow system-context boundary for anonymous portal enquiries.
 *
 * Guest users receive no direct CRUD/FLS access to Lead, Branch__c, or
 * LearningCourse. Only allow-listed DTO fields are accepted and every value is
 * validated again on the server before the enquiry is inserted.
 */
public without sharing class PublicEnquiryController {
  private static final Integer MIN_SUBMIT_MILLIS = 1500;
  private static final Integer MAX_FORM_AGE_MILLIS = 14400000;
  private static final Set<String> RELATIONSHIPS = new Set<String>{
    'Mother',
    'Father',
    'Guardian',
    'Grandparent',
    'Sibling',
    'Other'
  };
  private static final Set<String> DELIVERY_MODES = new Set<String>{
    'Classroom',
    'Online',
    'Hybrid'
  };

  public class SelectOption {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }

    SelectOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class FormData {
    @AuraEnabled
    public List<SelectOption> branches { get; set; }
    @AuraEnabled
    public List<SelectOption> courses { get; set; }
    @AuraEnabled
    public List<SelectOption> relationships { get; set; }
    @AuraEnabled
    public List<SelectOption> deliveryModes { get; set; }
  }

  public class SubmissionRequest {
    @AuraEnabled
    public String submissionId { get; set; }
    @AuraEnabled
    public Long formStartedAt { get; set; }
    @AuraEnabled
    public String website { get; set; }
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public Date birthdate { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String guardianFirstName { get; set; }
    @AuraEnabled
    public String guardianLastName { get; set; }
    @AuraEnabled
    public String guardianRelationship { get; set; }
    @AuraEnabled
    public String guardianEmail { get; set; }
    @AuraEnabled
    public String guardianPhone { get; set; }
    @AuraEnabled
    public String branchCode { get; set; }
    @AuraEnabled
    public String courseExternalId { get; set; }
    @AuraEnabled
    public String deliveryMode { get; set; }
    @AuraEnabled
    public String referralCode { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public Boolean privacyConsent { get; set; }
  }

  public class SubmissionResult {
    @AuraEnabled
    public Boolean accepted { get; set; }
    @AuraEnabled
    public String reference { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static FormData getFormData() {
    FormData data = new FormData();
    data.branches = new List<SelectOption>();
    data.courses = new List<SelectOption>();
    data.relationships = options(RELATIONSHIPS);
    data.deliveryModes = options(DELIVERY_MODES);

    for (Branch__c branch : [
      SELECT Name, Branch_Code__c
      FROM Branch__c
      WHERE Active__c = TRUE AND Branch_Code__c != NULL
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      data.branches.add(new SelectOption(branch.Name, branch.Branch_Code__c));
    }
    for (LearningCourse course : [
      SELECT Name, External_ID__c
      FROM LearningCourse
      WHERE Learning.IsActive = TRUE AND External_ID__c != NULL
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      data.courses.add(new SelectOption(course.Name, course.External_ID__c));
    }
    return data;
  }

  @AuraEnabled
  public static SubmissionResult submit(SubmissionRequest request) {
    try {
      return save(request);
    } catch (AppException e) {
      throw handled(e.getMessage());
    } catch (Exception e) {
      Logger.error('PublicEnquiryController.submit', e, null);
      throw handled(
        'We could not submit your enquiry. Please try again later.'
      );
    }
  }

  @TestVisible
  private static SubmissionResult save(SubmissionRequest request) {
    validate(request);

    List<Lead> prior = [
      SELECT Id
      FROM Lead
      WHERE Submission_Id__c = :request.submissionId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!prior.isEmpty()) {
      return resultFor(request.submissionId);
    }

    Branch__c branch = findBranch(request.branchCode);
    Id courseId = findCourse(request.courseExternalId);
    Lead enquiry = new Lead(
      Submission_Id__c = request.submissionId,
      FirstName = clean(request.firstName),
      LastName = clean(request.lastName),
      Learner_Birthdate__c = request.birthdate,
      Email = clean(request.email),
      MobilePhone = clean(request.phone),
      Guardian_First_Name__c = clean(request.guardianFirstName),
      Guardian_Last_Name__c = clean(request.guardianLastName),
      Guardian_Relationship__c = clean(request.guardianRelationship),
      Guardian_Email__c = clean(request.guardianEmail),
      Guardian_Phone__c = clean(request.guardianPhone),
      Branch__c = branch.Id,
      Interested_Course__c = courseId,
      Preferred_Delivery_Mode__c = clean(request.deliveryMode),
      Referral_Code__c = clean(request.referralCode),
      Description = clean(request.message),
      Privacy_Consent__c = true,
      Privacy_Consent_Date__c = System.now(),
      Enquiry_Channel__c = 'Website',
      LeadSource = 'Web'
    );
    Database.insert(enquiry, AccessLevel.SYSTEM_MODE);
    return resultFor(request.submissionId);
  }

  @TestVisible
  private static void validate(SubmissionRequest request) {
    if (request == null) {
      fail('Complete the enquiry form before submitting.');
    }
    if (String.isNotBlank(request.website)) {
      fail('The enquiry could not be accepted.');
    }
    Long nowMillis = DateTime.now().getTime();
    if (
      request.formStartedAt == null ||
      request.formStartedAt > nowMillis ||
      nowMillis - request.formStartedAt < MIN_SUBMIT_MILLIS ||
      nowMillis - request.formStartedAt > MAX_FORM_AGE_MILLIS
    ) {
      fail('Refresh the page and complete the form again.');
    }
    String key = clean(request.submissionId);
    if (
      String.isBlank(key) ||
      key.length() > 80 ||
      !Pattern.matches('^portal-[A-Za-z0-9-]{20,73}$', key)
    ) {
      fail('Refresh the page and complete the form again.');
    }
    required(request.lastName, 80, 'Learner last name');
    optional(request.firstName, 40, 'Learner first name');
    required(request.branchCode, 40, 'Branch');
    optional(request.email, 80, 'Learner email');
    optional(request.phone, 40, 'Learner mobile');
    optional(request.guardianFirstName, 40, 'Guardian first name');
    optional(request.guardianLastName, 80, 'Guardian last name');
    optional(request.guardianEmail, 80, 'Guardian email');
    optional(request.guardianPhone, 40, 'Guardian phone');
    optional(request.courseExternalId, 100, 'Interested course');
    optional(request.referralCode, 20, 'Referral code');
    optional(request.message, 2000, 'Message');

    if (
      String.isBlank(request.email) &&
      String.isBlank(request.phone) &&
      String.isBlank(request.guardianEmail) &&
      String.isBlank(request.guardianPhone)
    ) {
      fail('Enter at least one email address or phone number.');
    }
    validEmail(request.email, 'Learner email');
    validEmail(request.guardianEmail, 'Guardian email');
    validPhone(request.phone, 'Learner mobile');
    validPhone(request.guardianPhone, 'Guardian phone');
    if (
      String.isNotBlank(request.guardianRelationship) &&
      !RELATIONSHIPS.contains(request.guardianRelationship)
    ) {
      fail('Select a valid guardian relationship.');
    }
    if (
      String.isNotBlank(request.deliveryMode) &&
      !DELIVERY_MODES.contains(request.deliveryMode)
    ) {
      fail('Select a valid delivery mode.');
    }
    if (
      request.birthdate != null &&
      (request.birthdate > Date.today() ||
      request.birthdate < Date.today().addYears(-120))
    ) {
      fail('Enter a valid learner date of birth.');
    }
    if (request.privacyConsent != true) {
      fail('Privacy consent is required.');
    }
  }

  private static Branch__c findBranch(String branchCode) {
    List<Branch__c> branches = [
      SELECT Id
      FROM Branch__c
      WHERE Branch_Code__c = :branchCode AND Active__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (branches.isEmpty()) {
      fail('Select an active branch.');
    }
    return branches[0];
  }

  private static Id findCourse(String externalId) {
    if (String.isBlank(externalId)) {
      return null;
    }
    List<LearningCourse> courses = [
      SELECT Id
      FROM LearningCourse
      WHERE External_ID__c = :externalId AND Learning.IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (courses.isEmpty()) {
      fail('Select an active course.');
    }
    return courses[0].Id;
  }

  private static void validEmail(String value, String label) {
    if (
      String.isNotBlank(value) &&
      !Pattern.matches('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$', value.trim())
    ) {
      fail(label + ' is not valid.');
    }
  }

  private static void validPhone(String value, String label) {
    if (String.isBlank(value)) {
      return;
    }
    String digits = value.replaceAll('[^0-9]', '');
    if (digits.length() < 7 || digits.length() > 15) {
      fail(label + ' is not valid.');
    }
  }

  private static void required(String value, Integer max, String label) {
    if (String.isBlank(value)) {
      fail(label + ' is required.');
    }
    optional(value, max, label);
  }

  private static void optional(String value, Integer max, String label) {
    if (value != null && value.trim().length() > max) {
      fail(label + ' must be ' + max + ' characters or fewer.');
    }
  }

  private static List<SelectOption> options(Set<String> values) {
    List<String> sortedValues = new List<String>(values);
    sortedValues.sort();
    List<SelectOption> result = new List<SelectOption>();
    for (String value : sortedValues) {
      result.add(new SelectOption(value, value));
    }
    return result;
  }

  private static SubmissionResult resultFor(String submissionId) {
    SubmissionResult result = new SubmissionResult();
    result.accepted = true;
    result.reference = submissionId.right(12).toUpperCase();
    return result;
  }

  private static String clean(String value) {
    return value == null ? null : value.trim();
  }

  private static void fail(String message) {
    throw new AppException(message);
  }

  private static AuraHandledException handled(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
