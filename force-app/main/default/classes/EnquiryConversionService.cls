/**
 * Converts a qualified enquiry into a learner (Person Account), an optional
 * guardian (Person Account) linked through ContactContactRelation, and an
 * admissions application. The Lead is converted with standard lead
 * conversion into the learner account so conversion reporting keeps working.
 * The whole operation is atomic.
 *
 * A college enquiry (from the public college page, Lead.Campus_Branch__c set)
 * becomes a college admission instead: same intake, route and declared marks,
 * which the desk confirms against the marks card while converting.
 */
public with sharing class EnquiryConversionService {
  public class ConversionRequest {
    @AuraEnabled
    public Id leadId { get; set; }
    @AuraEnabled
    public Id existingLearnerId { get; set; }
    @AuraEnabled
    public Id existingGuardianId { get; set; }
    @AuraEnabled
    public Boolean createGuardian { get; set; }
    @AuraEnabled
    public Boolean createApplication { get; set; }
    /** College enquiries: the desk has checked the marks against the marks card. */
    @AuraEnabled
    public Boolean marksConfirmed { get; set; }
    /** College enquiries: the marks as confirmed (or corrected) by the desk. */
    @AuraEnabled
    public List<CollegeAdmissionController.Qualification> qualifications {
      get;
      set;
    }
    @AuraEnabled
    public List<CollegeAdmissionController.Entrance> entrances { get; set; }
  }

  /** What the visitor declared on the public college enquiry. */
  public class CollegeEnquiry {
    @AuraEnabled
    public Id campusBranchId;
    @AuraEnabled
    public String campusBranchName;
    @AuraEnabled
    public String entryRoute;
    @AuraEnabled
    public Boolean consent;
    @AuraEnabled
    public List<CollegeAdmissionController.Qualification> qualifications;
    @AuraEnabled
    public List<CollegeAdmissionController.Entrance> entrances;
    @AuraEnabled
    public Boolean canConvert;
  }

  public class ConversionResult {
    @AuraEnabled
    public Id learnerId;
    @AuraEnabled
    public Id guardianId;
    @AuraEnabled
    public Id applicationId;
    @AuraEnabled
    public Boolean learnerCreated = false;
    @AuraEnabled
    public Boolean guardianCreated = false;
    /** True when a college admission was created: the desk continues there. */
    @AuraEnabled
    public Boolean college = false;
  }

  public class ConversionPreview {
    @AuraEnabled
    public Lead enquiry;
    @AuraEnabled
    public Account learnerMatch;
    @AuraEnabled
    public Account guardianMatch;
    @AuraEnabled
    public Boolean hasGuardianDetails;
    /** Set for college enquiries only. */
    @AuraEnabled
    public CollegeEnquiry college;
  }

  public static ConversionPreview preview(Id leadId) {
    ConversionPreview result = new ConversionPreview();
    result.enquiry = loadLead(leadId);
    result.college = loadCollege(leadId);
    result.learnerMatch = PersonAccountService.findPerson(
      result.enquiry.Email,
      firstNonBlank(result.enquiry.MobilePhone, result.enquiry.Phone),
      result.enquiry.LastName
    );
    result.hasGuardianDetails = String.isNotBlank(
      result.enquiry.Guardian_Last_Name__c
    );
    if (result.hasGuardianDetails) {
      result.guardianMatch = PersonAccountService.findPerson(
        result.enquiry.Guardian_Email__c,
        result.enquiry.Guardian_Phone__c,
        result.enquiry.Guardian_Last_Name__c
      );
    }
    return result;
  }

  public static ConversionResult convert(ConversionRequest request) {
    Lead enquiry = loadLead(request.leadId);
    if (enquiry.IsConverted) {
      throw new AppException('This enquiry has already been converted.');
    }
    if (enquiry.Branch__c == null) {
      throw new AppException(
        'Select a branch on the enquiry before converting it.'
      );
    }
    CollegeEnquiry college = loadCollege(enquiry.Id);
    if (college != null) {
      RecordAccess.assertPermission(CollegeDocumentService.VERIFY_PERMISSION);
      if (request.marksConfirmed != true) {
        throw new AppException(
          'Check the declared marks against the marks card before converting.'
        );
      }
    }
    Savepoint sp = Database.setSavepoint();
    try {
      ConversionResult result = new ConversionResult();
      Account learner = resolveLearner(enquiry, request, result);
      Account guardian = resolveGuardian(enquiry, request, result);

      Map<Id, Account> people = PersonAccountService.reload(
        guardian == null
          ? new Set<Id>{ learner.Id }
          : new Set<Id>{ learner.Id, guardian.Id }
      );
      learner = people.get(learner.Id);
      if (guardian != null) {
        guardian = people.get(guardian.Id);
        GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
        link.guardianContactId = guardian.PersonContactId;
        link.learnerContactId = learner.PersonContactId;
        link.relationship = enquiry.Guardian_Relationship__c;
        // College parents get portal access only when the desk grants it later.
        link.portalAccess = college == null;
        GuardianRelationshipService.link(
          new List<GuardianRelationshipService.GuardianLink>{ link }
        );
      }

      if (college != null) {
        result.applicationId = createCollegeAdmission(
          enquiry,
          college,
          request,
          learner
        );
        result.college = true;
      } else if (request.createApplication != false) {
        IndividualApplication application = new IndividualApplication(
          Category = 'Education',
          RecordTypeId = admissionsRecordTypeId(),
          AccountId = learner.Id,
          ContactId = learner.PersonContactId,
          Status = 'Processing',
          AppliedDate = System.now(),
          Branch__c = enquiry.Branch__c,
          Learning_Course__c = enquiry.Interested_Course__c,
          Learning_Program__c = enquiry.Interested_Program__c
        );
        Database.insert(application, AccessLevel.USER_MODE);
        result.applicationId = application.Id;
        // Traceability fields are read-only for users; the service stamps them.
        Database.update(
          new IndividualApplication(
            Id = application.Id,
            Source_Enquiry__c = enquiry.Id
          ),
          AccessLevel.SYSTEM_MODE
        );
      }

      // Converted leads are read-only, so link the outcome before converting.
      // The user's edit access to the enquiry is proven first (user mode);
      // the read-only traceability fields are then stamped in system mode.
      Database.update(
        new Lead(Id = enquiry.Id, Company = null),
        AccessLevel.USER_MODE
      );
      Database.update(
        new Lead(
          Id = enquiry.Id,
          Converted_Learner__c = learner.Id,
          Converted_Application__c = result.applicationId
        ),
        AccessLevel.SYSTEM_MODE
      );
      Database.LeadConvert conversion = new Database.LeadConvert();
      conversion.setLeadId(enquiry.Id);
      conversion.setAccountId(learner.Id);
      conversion.setContactId(learner.PersonContactId);
      conversion.setDoNotCreateOpportunity(true);
      conversion.setConvertedStatus(convertedStatus());
      Database.LeadConvertResult converted = Database.convertLead(
        conversion,
        false
      );
      if (!converted.isSuccess()) {
        throw new AppException(converted.getErrors()[0].getMessage());
      }
      result.learnerId = learner.Id;
      result.guardianId = guardian == null ? null : guardian.Id;
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      Logger.error('EnquiryConversionService.convert', e, request.leadId);
      throw e;
    }
  }

  private static Account resolveLearner(
    Lead enquiry,
    ConversionRequest request,
    ConversionResult result
  ) {
    if (request.existingLearnerId != null) {
      Account existing = PersonAccountService.reload(
          new Set<Id>{ request.existingLearnerId }
        )
        .get(request.existingLearnerId);
      if (existing == null || existing.PersonContactId == null) {
        throw new AppException(
          'The selected learner is not a person account you can access.'
        );
      }
      String role = PersonAccountService.mergeRole(
        existing.KEM_Role__c,
        'Learner'
      );
      if (role != existing.KEM_Role__c) {
        Database.update(
          new Account(Id = existing.Id, KEM_Role__c = role),
          AccessLevel.USER_MODE
        );
      }
      return existing;
    }
    Account learner = PersonAccountService.buildPerson(
      enquiry.FirstName,
      enquiry.LastName,
      enquiry.Email,
      firstNonBlank(enquiry.MobilePhone, enquiry.Phone),
      enquiry.Branch__c,
      'Learner'
    );
    learner.PersonBirthdate = enquiry.Learner_Birthdate__c;
    Database.insert(learner, AccessLevel.USER_MODE);
    result.learnerCreated = true;
    return learner;
  }

  private static Account resolveGuardian(
    Lead enquiry,
    ConversionRequest request,
    ConversionResult result
  ) {
    if (request.existingGuardianId != null) {
      Account existing = PersonAccountService.reload(
          new Set<Id>{ request.existingGuardianId }
        )
        .get(request.existingGuardianId);
      if (existing == null || existing.PersonContactId == null) {
        throw new AppException(
          'The selected guardian is not a person account you can access.'
        );
      }
      String role = PersonAccountService.mergeRole(
        existing.KEM_Role__c,
        'Guardian'
      );
      if (role != existing.KEM_Role__c) {
        Database.update(
          new Account(Id = existing.Id, KEM_Role__c = role),
          AccessLevel.USER_MODE
        );
      }
      return existing;
    }
    if (
      request.createGuardian == false ||
      String.isBlank(enquiry.Guardian_Last_Name__c)
    ) {
      return null;
    }
    Account guardian = PersonAccountService.buildPerson(
      enquiry.Guardian_First_Name__c,
      enquiry.Guardian_Last_Name__c,
      enquiry.Guardian_Email__c,
      enquiry.Guardian_Phone__c,
      enquiry.Branch__c,
      'Guardian'
    );
    Database.insert(guardian, AccessLevel.USER_MODE);
    result.guardianCreated = true;
    return guardian;
  }

  private static Id createCollegeAdmission(
    Lead enquiry,
    CollegeEnquiry college,
    ConversionRequest request,
    Account learner
  ) {
    CollegeAdmissionController.NewAdmission admission = new CollegeAdmissionController.NewAdmission();
    admission.firstName = enquiry.FirstName;
    admission.lastName = enquiry.LastName;
    admission.email = enquiry.Email;
    admission.phone = firstNonBlank(enquiry.MobilePhone, enquiry.Phone);
    admission.birthdate = enquiry.Learner_Birthdate__c;
    admission.campusBranchId = college.campusBranchId;
    admission.entryRoute = college.entryRoute;
    admission.qualifications = request.qualifications != null
      ? request.qualifications
      : college.qualifications;
    admission.entrances = request.entrances != null
      ? request.entrances
      : college.entrances;
    // The visitor agreed to the privacy notice on the public page.
    admission.consent = college.consent;
    // Same rules as the public self-check: open intake, valid route and marks.
    CollegePublicController.validateDeclaration(
      admission.campusBranchId,
      admission.entryRoute,
      admission.qualifications,
      admission.entrances
    );
    Id applicationId = CollegeAdmissionService.create(admission, learner.Id);
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        Source_Enquiry__c = enquiry.Id
      ),
      AccessLevel.SYSTEM_MODE
    );
    return applicationId;
  }

  /**
   * College fields are read in system mode so a school counsellor without the
   * college field access can still convert school enquiries; the college path
   * itself is guarded by the desk permission in convert().
   */
  private static CollegeEnquiry loadCollege(Id leadId) {
    Lead row = [
      SELECT
        Campus_Branch__c,
        Campus_Branch__r.Campus__r.Name,
        Campus_Branch__r.Branch__r.Name,
        Campus_Branch__r.Academic_Year__c,
        Entry_Route__c,
        Declared_Marks__c,
        Privacy_Consent__c
      FROM Lead
      WHERE Id = :leadId
      WITH SYSTEM_MODE
    ];
    if (row.Campus_Branch__c == null) {
      return null;
    }
    CollegeEnquiry college = new CollegeEnquiry();
    college.campusBranchId = row.Campus_Branch__c;
    // Campus branch names are auto-numbers; show what the desk recognises.
    college.campusBranchName =
      row.Campus_Branch__r.Campus__r.Name +
      ' · ' +
      row.Campus_Branch__r.Branch__r.Name +
      ' · ' +
      row.Campus_Branch__r.Academic_Year__c;
    college.entryRoute = String.isBlank(row.Entry_Route__c)
      ? 'Regular'
      : row.Entry_Route__c;
    college.consent = row.Privacy_Consent__c;
    college.qualifications = new List<CollegeAdmissionController.Qualification>();
    college.entrances = new List<CollegeAdmissionController.Entrance>();
    if (String.isNotBlank(row.Declared_Marks__c)) {
      PublicEnquiryController.Declaration declared = (PublicEnquiryController.Declaration) JSON.deserialize(
        row.Declared_Marks__c,
        PublicEnquiryController.Declaration.class
      );
      if (declared.qualifications != null) {
        college.qualifications = declared.qualifications;
      }
      if (declared.entrances != null) {
        college.entrances = declared.entrances;
      }
    }
    college.canConvert = FeatureManagement.checkPermission(
      CollegeDocumentService.VERIFY_PERMISSION
    );
    return college;
  }

  private static Lead loadLead(Id leadId) {
    List<Lead> leads = [
      SELECT
        Id,
        FirstName,
        LastName,
        Email,
        Phone,
        MobilePhone,
        Status,
        IsConverted,
        Branch__c,
        Branch__r.Name,
        Interested_Course__c,
        Interested_Course__r.Name,
        Interested_Program__c,
        Interested_Program__r.Name,
        Learner_Birthdate__c,
        Guardian_First_Name__c,
        Guardian_Last_Name__c,
        Guardian_Email__c,
        Guardian_Phone__c,
        Guardian_Relationship__c,
        Possible_Duplicate__c,
        Duplicate_Details__c
      FROM Lead
      WHERE Id = :leadId
      WITH USER_MODE
    ];
    if (leads.isEmpty()) {
      throw new AppException('Enquiry not found or not accessible.');
    }
    return leads[0];
  }

  private static String convertedStatus() {
    return [
      SELECT MasterLabel
      FROM LeadStatus
      WHERE IsConverted = TRUE
      ORDER BY SortOrder
      LIMIT 1
    ]
    .MasterLabel;
  }

  private static Id admissionsRecordTypeId() {
    Schema.RecordTypeInfo info = Schema.SObjectType.IndividualApplication.getRecordTypeInfosByDeveloperName()
      .get('Admissions');
    return info == null ? null : info.getRecordTypeId();
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }
}
