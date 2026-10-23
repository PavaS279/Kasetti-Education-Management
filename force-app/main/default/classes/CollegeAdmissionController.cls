/**
 * Lightning boundary for the college admission desk and the Dean: new admission
 * with a live eligibility verdict, consent, document verification, interview,
 * admit and reject. Every action delegates to the C2/C3 services, which enforce
 * permissions, stages and record access.
 */
public with sharing class CollegeAdmissionController {
  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class Qualification {
    @AuraEnabled
    public String level { get; set; }
    @AuraEnabled
    public String stream { get; set; }
    @AuraEnabled
    public String branchCode { get; set; }
    @AuraEnabled
    public Decimal percentage { get; set; }
    @AuraEnabled
    public Integer year { get; set; }
  }

  public class Entrance {
    @AuraEnabled
    public String exam { get; set; }
    @AuraEnabled
    public Integer rank { get; set; }
    @AuraEnabled
    public Integer year { get; set; }
  }

  public class NewAdmission {
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public Date birthdate { get; set; }
    @AuraEnabled
    public Id campusBranchId { get; set; }
    @AuraEnabled
    public String entryRoute { get; set; }
    @AuraEnabled
    public List<Qualification> qualifications { get; set; }
    @AuraEnabled
    public List<Entrance> entrances { get; set; }
    @AuraEnabled
    public String guardianFirstName { get; set; }
    @AuraEnabled
    public String guardianLastName { get; set; }
    @AuraEnabled
    public String guardianPhone { get; set; }
    /** The student (or parent) agreed to the privacy notice at the desk. */
    @AuraEnabled
    public Boolean consent { get; set; }
  }

  public class BranchChoice {
    @AuraEnabled
    public Id campusBranchId;
    @AuraEnabled
    public String externalId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public Decimal seatsRegular;
    @AuraEnabled
    public Decimal seatsLateral;
    @AuraEnabled
    public String cutoff;
    @AuraEnabled
    public Boolean lateral = false;
  }

  public class ProgrammeChoice {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public Decimal years;
    @AuraEnabled
    public List<BranchChoice> branches = new List<BranchChoice>();
  }

  public class CampusChoice {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String academicYear;
    @AuraEnabled
    public List<ProgrammeChoice> programmes = new List<ProgrammeChoice>();
  }

  public class EntranceOption {
    @AuraEnabled
    public String exam;
    @AuraEnabled
    public Decimal maxRank;
  }

  public class DocumentNeed {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public String sensitiveClass;
  }

  public class Requirements {
    @AuraEnabled
    public Boolean open = false;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String qualifyingLevel;
    @AuraEnabled
    public List<String> streams = new List<String>();
    @AuraEnabled
    public List<String> diplomaBranchCodes = new List<String>();
    @AuraEnabled
    public Decimal minimum;
    @AuraEnabled
    public Boolean entranceRequired = false;
    @AuraEnabled
    public List<EntranceOption> entrances = new List<EntranceOption>();
    @AuraEnabled
    public Decimal entryYear;
    @AuraEnabled
    public Decimal seatsLeft;
    @AuraEnabled
    public Decimal tuition;
    @AuraEnabled
    public Decimal admissionFee;
    @AuraEnabled
    public List<DocumentNeed> documents = new List<DocumentNeed>();
  }

  public class Item {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String sensitiveClass;
    @AuraEnabled
    public String last4;
    @AuraEnabled
    public Boolean fileDeleted;
  }

  public class Admission {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String student;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String campus;
    @AuraEnabled
    public String entryRoute;
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public String eligibility;
    @AuraEnabled
    public String eligibilityNotes;
    @AuraEnabled
    public List<String> suggestions = new List<String>();
    @AuraEnabled
    public Boolean consent;
    @AuraEnabled
    public Datetime interviewAt;
    @AuraEnabled
    public String interviewer;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public String decision;
    @AuraEnabled
    public String decisionReason;
    @AuraEnabled
    public Id programmeEnrolmentId;
    @AuraEnabled
    public String rollNumber;
    @AuraEnabled
    public String enrolmentStatus;
    @AuraEnabled
    public List<Item> items = new List<Item>();
    @AuraEnabled
    public Boolean canDesk = false;
    @AuraEnabled
    public Boolean canDean = false;
  }

  /** Campus branches open for admission in the current intake. */
  @AuraEnabled(cacheable=true)
  public static List<Option> getIntakes() {
    try {
      List<Option> result = new List<Option>();
      for (Campus_Branch__c cb : [
        SELECT Id, Academic_Year__c, Campus__r.Name, Branch__r.Name
        FROM Campus_Branch__c
        WHERE Admissions_Open__c = TRUE
        WITH USER_MODE
        ORDER BY Campus__r.Name, Branch__r.Name
        LIMIT 200
      ]) {
        Option o = new Option();
        o.value = cb.Id;
        o.label =
          cb.Campus__r.Name +
          ' · ' +
          cb.Branch__r.Name +
          ' · ' +
          cb.Academic_Year__c;
        result.add(o);
      }
      return result;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Campuses → programmes → branches open for admission, with seats left and the regular cut-off. */
  @AuraEnabled(cacheable=true)
  public static List<CampusChoice> getAdmissionCatalogue() {
    try {
      return CollegeAdmissionCatalog.catalogue();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** What the desk must ask for this campus branch and route: marks, stream, entrance, documents and fees. */
  @AuraEnabled(cacheable=true)
  public static Requirements getRequirements(
    Id campusBranchId,
    String entryRoute
  ) {
    try {
      return CollegeAdmissionCatalog.requirements(campusBranchId, entryRoute);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Live eligibility for what the desk has typed so far; nothing is saved. */
  @AuraEnabled
  public static AdmissionEligibilityService.Preview previewEligibility(
    Id campusBranchId,
    String entryRoute,
    List<Qualification> qualifications,
    List<Entrance> entrances
  ) {
    try {
      List<Academic_Qualification__c> declared = new List<Academic_Qualification__c>();
      for (
        Qualification q : qualifications == null
          ? new List<Qualification>()
          : qualifications
      ) {
        if (String.isBlank(q.level) || q.percentage == null) {
          continue;
        }
        declared.add(
          new Academic_Qualification__c(
            Level__c = q.level,
            Stream_Group__c = String.isBlank(q.stream) ? null : q.stream,
            Branch_Code__c = String.isBlank(q.branchCode)
              ? null
              : q.branchCode.toUpperCase(),
            Percentage__c = q.percentage
          )
        );
      }
      List<Entrance_Score__c> scores = new List<Entrance_Score__c>();
      for (Entrance e : entrances == null ? new List<Entrance>() : entrances) {
        if (String.isBlank(e.exam) || e.rank == null) {
          continue;
        }
        scores.add(
          new Entrance_Score__c(
            Exam__c = e.exam,
            Rank__c = e.rank,
            Exam_Year__c = e.year == null ? Date.today().year() : e.year
          )
        );
      }
      return AdmissionEligibilityService.preview(
        campusBranchId,
        entryRoute,
        declared,
        scores
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission createAdmission(NewAdmission request) {
    try {
      return load(CollegeAdmissionService.create(request));
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission getAdmission(Id applicationId) {
    try {
      RecordAccess.assertReadable(applicationId);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission captureConsent(Id applicationId) {
    try {
      CollegeDocumentService.captureConsent(applicationId);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission verifyDocument(
    Id applicationId,
    Id itemId,
    String last4
  ) {
    try {
      CollegeDocumentService.verify(itemId, last4);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission markDocumentsVerified(Id applicationId) {
    try {
      CollegeDocumentService.markDocumentsVerified(applicationId);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission scheduleInterview(
    Id applicationId,
    Datetime interviewAt
  ) {
    try {
      InterviewService.schedule(
        applicationId,
        interviewAt,
        UserInfo.getUserId()
      );
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission recordOutcome(
    Id applicationId,
    String outcome,
    String remarks
  ) {
    try {
      InterviewService.recordOutcome(applicationId, outcome, remarks);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission admit(Id applicationId) {
    try {
      InterviewService.admit(applicationId);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Admission reject(Id applicationId, String reason) {
    try {
      InterviewService.reject(applicationId, reason);
      return load(applicationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  private static Admission load(Id applicationId) {
    IndividualApplication a = [
      SELECT
        Id,
        College_Mode__c,
        College_Stage__c,
        Entry_Route__c,
        Eligibility_Status__c,
        Eligibility_Notes__c,
        Privacy_Consent__c,
        Interview_Date__c,
        Interviewer__r.Name,
        Interview_Outcome__c,
        Decision__c,
        Decision_Reason__c,
        Account.Name,
        Learning_Course__r.Name,
        Branch__r.Name
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (!a.College_Mode__c) {
      return null; // learning-centre applications: the panel stays hidden
    }
    Admission result = new Admission();
    result.id = a.Id;
    result.student = a.Account.Name;
    result.branch = a.Learning_Course__r.Name;
    result.campus = a.Branch__r.Name;
    result.entryRoute = a.Entry_Route__c;
    result.stage = a.College_Stage__c;
    result.eligibility = a.Eligibility_Status__c;
    result.eligibilityNotes = a.Eligibility_Notes__c;
    result.consent = a.Privacy_Consent__c;
    result.interviewAt = a.Interview_Date__c;
    result.interviewer = a.Interviewer__r?.Name;
    result.outcome = a.Interview_Outcome__c;
    result.decision = a.Decision__c;
    result.decisionReason = a.Decision_Reason__c;
    if (a.Eligibility_Status__c == 'Not Eligible') {
      result.suggestions = AdmissionEligibilityService.suggestions(a.Id);
    }
    for (DocumentChecklistItem item : [
      SELECT
        Id,
        Name,
        IsRequired,
        Status,
        Sensitive_Class__c,
        Last4__c,
        File_Deleted_On__c
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :a.Id
      WITH SYSTEM_MODE
      ORDER BY Name
    ]) {
      Item row = new Item();
      row.id = item.Id;
      row.name = item.Name;
      row.required = item.IsRequired;
      row.status = item.Status;
      row.sensitiveClass = item.Sensitive_Class__c;
      row.last4 = item.Last4__c;
      row.fileDeleted = item.File_Deleted_On__c != null;
      result.items.add(row);
    }
    for (Programme_Enrolment__c e : [
      SELECT Id, Status__c, Roll_Number__c
      FROM Programme_Enrolment__c
      WHERE Application__c = :a.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      result.programmeEnrolmentId = e.Id;
      result.rollNumber = e.Roll_Number__c;
      result.enrolmentStatus = e.Status__c;
    }
    result.canDesk = Schema.SObjectType.DocumentChecklistItem.isUpdateable();
    result.canDean = FeatureManagement.checkPermission(
      InterviewService.PERMISSION
    );
    return result;
  }
}
