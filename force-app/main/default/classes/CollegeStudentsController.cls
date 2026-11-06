/**
 * College Students tab: every college student (admitted with the fee pending,
 * enrolled, or finished) with roll number, programme, section, fees due and
 * portal access, so staff can open each student's 360 page and academic record.
 *
 * Programme enrolments are private records owned by whoever admitted the
 * student, so the list is read without sharing after an explicit check that
 * the user is the Dean or the admission desk (the same people who work these
 * admissions). Nothing is written here.
 */
public without sharing class CollegeStudentsController {
  private static final Set<String> CURRENT = new Set<String>{
    'Provisional',
    'Enrolled'
  };
  private static final Set<String> OPEN_INVOICE = new Set<String>{
    'Issued',
    'Partially Paid'
  };

  public class Student {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public Id applicationId;
    @AuraEnabled
    public String usn;
    @AuraEnabled
    public Id studentId;
    @AuraEnabled
    public String student;
    @AuraEnabled
    public String rollNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String campus;
    @AuraEnabled
    public Id campusId;
    @AuraEnabled
    public String programme;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Decimal yearOfStudy;
    @AuraEnabled
    public String academicYear;
    @AuraEnabled
    public String entryRoute;
    @AuraEnabled
    public String section;
    @AuraEnabled
    public Decimal feesDue = 0;
    @AuraEnabled
    public Date paymentDueBy;
    @AuraEnabled
    public Boolean hasEmail = false;
    @AuraEnabled
    public Boolean hasPortal = false;
  }

  public class Summary {
    @AuraEnabled
    public Integer enrolled = 0;
    @AuraEnabled
    public Integer feePending = 0;
    @AuraEnabled
    public Integer withoutSection = 0;
    @AuraEnabled
    public Decimal feesDue = 0;
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class StudentList {
    @AuraEnabled
    public List<Student> students = new List<Student>();
    @AuraEnabled
    public Summary summary = new Summary();
    @AuraEnabled
    public List<Option> campuses = new List<Option>();
    /** May enter a USN (college staff); changing one needs a System Administrator. */
    @AuraEnabled
    public Boolean canSetUsn = false;
    @AuraEnabled
    public Boolean canChangeUsn = false;
  }

  /**
   * @param scope 'current' (fee pending and enrolled, the default) or 'all'
   *        (also completed, discontinued, expired and cancelled)
   */
  /** Enter (or, as a System Administrator, change with a reason) a student's USN. */
  @AuraEnabled
  public static void setUsn(Id enrolmentId, String usn, String reason) {
    try {
      CollegeUsnService.setUsn(enrolmentId, usn, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static StudentList getStudents(String scope) {
    try {
      assertCollegeStaff();
      return load(scope == 'all');
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @TestVisible
  private static void assertCollegeStaff() {
    if (
      !FeatureManagement.checkPermission(InterviewService.PERMISSION) &&
      !FeatureManagement.checkPermission(
        CollegeDocumentService.VERIFY_PERMISSION
      )
    ) {
      throw new AppException(
        'Only the college admission desk and the Dean can see the student list.'
      );
    }
  }

  private static StudentList load(Boolean everyone) {
    StudentList result = new StudentList();
    result.canSetUsn = CollegeUsnService.canSet();
    result.canChangeUsn = CollegeSetupController.canEdit();
    List<Programme_Enrolment__c> enrolments = everyone
      ? [
          SELECT
            Id,
            Student__c,
            Student__r.Name,
            Student__r.PersonEmail,
            Student__r.PersonContactId,
            Roll_Number__c,
            USN__c,
            Status__c,
            Application__c,
            Campus__c,
            Campus__r.Name,
            Programme__r.Name,
            Branch__r.Name,
            Current_Year_Of_Study__c,
            Academic_Year__c,
            Entry_Route__c,
            Payment_Due_By__c
          FROM Programme_Enrolment__c
          WITH SYSTEM_MODE
          ORDER BY Campus__r.Name, Branch__r.Name, Roll_Number__c NULLS LAST
          LIMIT 1000
        ]
      : [
          SELECT
            Id,
            Student__c,
            Student__r.Name,
            Student__r.PersonEmail,
            Student__r.PersonContactId,
            Roll_Number__c,
            USN__c,
            Status__c,
            Application__c,
            Campus__c,
            Campus__r.Name,
            Programme__r.Name,
            Branch__r.Name,
            Current_Year_Of_Study__c,
            Academic_Year__c,
            Entry_Route__c,
            Payment_Due_By__c
          FROM Programme_Enrolment__c
          WHERE Status__c IN :CURRENT
          WITH SYSTEM_MODE
          ORDER BY Campus__r.Name, Branch__r.Name, Roll_Number__c NULLS LAST
          LIMIT 1000
        ];
    if (enrolments.isEmpty()) {
      return result;
    }
    Set<Id> ids = new Map<Id, Programme_Enrolment__c>(enrolments).keySet();
    Set<Id> contactIds = new Set<Id>();
    for (Programme_Enrolment__c e : enrolments) {
      contactIds.add(e.Student__r.PersonContactId);
    }

    Map<Id, String> sectionOf = new Map<Id, String>();
    for (CourseOfferingParticipant participant : [
      SELECT Programme_Enrolment__c, CourseOffering.Name
      FROM CourseOfferingParticipant
      WHERE Programme_Enrolment__c IN :ids
      WITH SYSTEM_MODE
      ORDER BY CreatedDate ASC
    ]) {
      // The latest section wins (a promoted student has one per year).
      sectionOf.put(
        participant.Programme_Enrolment__c,
        participant.CourseOffering.Name
      );
    }
    Map<Id, Decimal> dueOf = new Map<Id, Decimal>();
    for (AggregateResult row : [
      SELECT Programme_Enrolment__c enrolment, SUM(Balance_Due__c) due
      FROM Student_Invoice__c
      WHERE Programme_Enrolment__c IN :ids AND Status__c IN :OPEN_INVOICE
      WITH SYSTEM_MODE
      GROUP BY Programme_Enrolment__c
    ]) {
      dueOf.put((Id) row.get('enrolment'), (Decimal) row.get('due'));
    }
    Set<Id> withPortal = new Set<Id>();
    for (User portalUser : [
      SELECT ContactId
      FROM User
      WHERE ContactId IN :contactIds AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      withPortal.add(portalUser.ContactId);
    }

    Map<Id, String> campuses = new Map<Id, String>();
    for (Programme_Enrolment__c e : enrolments) {
      Student row = new Student();
      row.enrolmentId = e.Id;
      row.applicationId = e.Application__c;
      row.studentId = e.Student__c;
      row.student = e.Student__r.Name;
      row.rollNumber = e.Roll_Number__c;
      row.usn = e.USN__c;
      row.status = e.Status__c;
      row.campusId = e.Campus__c;
      row.campus = e.Campus__r.Name;
      row.programme = e.Programme__r.Name;
      row.branch = e.Branch__r.Name;
      row.yearOfStudy = e.Current_Year_Of_Study__c;
      row.academicYear = e.Academic_Year__c;
      row.entryRoute = e.Entry_Route__c;
      row.section = sectionOf.get(e.Id);
      row.feesDue = dueOf.containsKey(e.Id) ? dueOf.get(e.Id) : 0;
      row.paymentDueBy = e.Payment_Due_By__c;
      row.hasEmail = String.isNotBlank(e.Student__r.PersonEmail);
      row.hasPortal = withPortal.contains(e.Student__r.PersonContactId);
      result.students.add(row);

      if (e.Status__c == 'Enrolled') {
        result.summary.enrolled++;
        if (row.section == null) {
          result.summary.withoutSection++;
        }
      } else if (e.Status__c == 'Provisional') {
        result.summary.feePending++;
      }
      result.summary.feesDue += row.feesDue;
      if (e.Campus__c != null) {
        campuses.put(e.Campus__c, e.Campus__r.Name);
      }
    }
    for (Id campusId : campuses.keySet()) {
      result.campuses.add(new Option(campuses.get(campusId), campusId));
    }
    return result;
  }
}
