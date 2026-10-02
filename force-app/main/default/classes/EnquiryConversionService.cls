/**
 * Converts a qualified enquiry into a learner (Person Account), an optional
 * guardian (Person Account) linked through ContactContactRelation, and an
 * admissions application. The Lead is converted with standard lead
 * conversion into the learner account so conversion reporting keeps working.
 * The whole operation is atomic.
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
  }

  public static ConversionPreview preview(Id leadId) {
    ConversionPreview result = new ConversionPreview();
    result.enquiry = loadLead(leadId);
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
        GuardianRelationshipService.link(
          new List<GuardianRelationshipService.GuardianLink>{ link }
        );
      }

      if (request.createApplication != false) {
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
