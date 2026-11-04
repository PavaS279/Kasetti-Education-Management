/** Lightning boundary for college joining, progression and results (Dean) and the student's academic summary. */
public with sharing class CollegeAcademicController {
  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class SubjectRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public Decimal term;
    @AuraEnabled
    public Decimal attempt;
    @AuraEnabled
    public Decimal internalMarks;
    @AuraEnabled
    public Decimal examMarks;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Decimal max;
    @AuraEnabled
    public String result;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String student;
    @AuraEnabled
    public Decimal attendancePercent;
  }

  public class EnrolmentPanel {
    @AuraEnabled
    public Programme_Enrolment__c enrolment;
    @AuraEnabled
    public String currentSection;
    @AuraEnabled
    public List<Option> sectionsThisYear = new List<Option>();
    @AuraEnabled
    public List<Option> sectionsNextYear = new List<Option>();
    @AuraEnabled
    public List<SubjectRow> subjects = new List<SubjectRow>();
    @AuraEnabled
    public List<Term_Result__c> terms = new List<Term_Result__c>();
    @AuraEnabled
    public Integer openBacklogs = 0;
    @AuraEnabled
    public Boolean canAct = false;
  }

  public class SectionSubjectRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String faculty;
    @AuraEnabled
    public Decimal term;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public List<SubjectRow> results = new List<SubjectRow>();
  }

  public class SectionPanel {
    @AuraEnabled
    public List<SectionSubjectRow> subjects = new List<SectionSubjectRow>();
    @AuraEnabled
    public Boolean canFinalise = false;
    @AuraEnabled
    public Boolean canReopen = false;
  }

  @AuraEnabled
  public static EnrolmentPanel getEnrolmentPanel(Id programmeEnrolmentId) {
    try {
      // Record access is checked in user mode; the panel is then read in system mode.
      RecordAccess.assertReadable(programmeEnrolmentId);
      EnrolmentPanel panel = new EnrolmentPanel();
      panel.enrolment = [
        SELECT
          Id,
          Name,
          Status__c,
          Roll_Number__c,
          Current_Year_Of_Study__c,
          Joining_Date__c,
          Academic_Year__c,
          Student__r.Name,
          Programme__r.Name,
          Programme__r.Duration_Years__c,
          Branch__r.Name,
          Campus__r.Name
        FROM Programme_Enrolment__c
        WHERE Id = :programmeEnrolmentId
        WITH SYSTEM_MODE
      ];
      panel.canAct = FeatureManagement.checkPermission(
        ProgressionService.DEAN_PERMISSION
      );
      Integer year = panel.enrolment.Current_Year_Of_Study__c.intValue();
      for (
        CourseOffering s : ProgressionService.eligibleSections(
          programmeEnrolmentId,
          year
        )
      ) {
        panel.sectionsThisYear.add(option(s));
      }
      for (
        CourseOffering s : ProgressionService.eligibleSections(
          programmeEnrolmentId,
          year + 1
        )
      ) {
        panel.sectionsNextYear.add(option(s));
      }
      List<CourseOfferingParticipant> sections = [
        SELECT Id, CourseOffering.Name
        FROM CourseOfferingParticipant
        WHERE Programme_Enrolment__c = :programmeEnrolmentId
        WITH SYSTEM_MODE
        ORDER BY Academic_Year__c DESC, Year_Of_Study__c DESC
        LIMIT 1
      ];
      panel.currentSection = sections.isEmpty()
        ? null
        : sections[0].CourseOffering.Name;
      Map<Id, Decimal> attendance = sections.isEmpty()
        ? new Map<Id, Decimal>()
        : subjectAttendance(sections[0].Id);
      for (
        Subject_Result__c r : resultsWhere(
          'Programme_Enrolment__c',
          programmeEnrolmentId
        )
      ) {
        SubjectRow row = row(r);
        row.attendancePercent = attendance.get(r.Section_Subject__c);
        panel.subjects.add(row);
      }
      panel.terms = [
        SELECT
          Id,
          Term__c,
          Status__c,
          Outcome__c,
          Subjects_Passed__c,
          Backlogs__c,
          Percentage__c
        FROM Term_Result__c
        WHERE Programme_Enrolment__c = :programmeEnrolmentId
        WITH SYSTEM_MODE
        ORDER BY Term__c
      ];
      panel.openBacklogs = ResultService.openBacklogs(programmeEnrolmentId)
        .size();
      return panel;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static SectionPanel getSectionPanel(Id sectionId) {
    try {
      RecordAccess.assertReadable(sectionId);
      SectionPanel panel = new SectionPanel();
      panel.canFinalise = FeatureManagement.checkPermission(
        ResultService.FINALISE_PERMISSION
      );
      panel.canReopen = FeatureManagement.checkPermission(
        ResultService.REOPEN_PERMISSION
      );
      Map<Id, SectionSubjectRow> rows = new Map<Id, SectionSubjectRow>();
      for (Section_Subject__c s : [
        SELECT Id, Term__c, Status__c, Subject__r.Name, Faculty__r.Name
        FROM Section_Subject__c
        WHERE Section__c = :sectionId
        WITH SYSTEM_MODE
        ORDER BY Term__c, Subject__r.Name
      ]) {
        SectionSubjectRow row = new SectionSubjectRow();
        row.id = s.Id;
        row.subject = s.Subject__r.Name;
        row.faculty = s.Faculty__r.Name;
        row.term = s.Term__c;
        row.status = s.Status__c;
        rows.put(s.Id, row);
      }
      if (!rows.isEmpty()) {
        for (Subject_Result__c r : resultsIn(rows.keySet())) {
          rows.get(r.Section_Subject__c).results.add(row(r));
        }
      }
      panel.subjects = rows.values();
      return panel;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id joinSection(
    Id programmeEnrolmentId,
    Id sectionId,
    Date joiningDate
  ) {
    try {
      return ProgressionService.join(
        programmeEnrolmentId,
        sectionId,
        joiningDate
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id promote(Id programmeEnrolmentId, Id sectionId) {
    try {
      return ProgressionService.promote(programmeEnrolmentId, sectionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id repeatYear(
    Id programmeEnrolmentId,
    Id sectionId,
    String reason
  ) {
    try {
      return ProgressionService.repeatYear(
        programmeEnrolmentId,
        sectionId,
        reason
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void discontinue(Id programmeEnrolmentId, String reason) {
    try {
      ProgressionService.discontinue(programmeEnrolmentId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id completeProgramme(Id programmeEnrolmentId) {
    try {
      return ProgressionService.completeProgramme(programmeEnrolmentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer finaliseResults(Id sectionSubjectId) {
    try {
      return ResultService.finalise(sectionSubjectId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void reopenResults(List<Id> subjectResultIds, String reason) {
    try {
      ResultService.reopen(new Set<Id>(subjectResultIds), reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Attendance percentage per section subject for one section enrolment (Present and Late count as attended). */
  public static Map<Id, Decimal> subjectAttendance(Id sectionEnrolmentId) {
    Map<Id, Integer> marked = new Map<Id, Integer>();
    Map<Id, Integer> attended = new Map<Id, Integer>();
    for (AggregateResult row : [
      SELECT
        Class_Session__r.Section_Subject__c subject,
        Status__c status,
        COUNT(Id) total
      FROM Session_Attendance__c
      WHERE
        Enrolment__c = :sectionEnrolmentId
        AND Class_Session__r.Section_Subject__c != NULL
      WITH SYSTEM_MODE
      GROUP BY Class_Session__r.Section_Subject__c, Status__c
    ]) {
      Id subject = (Id) row.get('subject');
      Integer total = (Integer) row.get('total');
      String status = (String) row.get('status');
      marked.put(
        subject,
        (marked.containsKey(subject) ? marked.get(subject) : 0) +
        (status == 'Excused' ? 0 : total)
      );
      if (status == 'Present' || status == 'Late') {
        attended.put(
          subject,
          (attended.containsKey(subject) ? attended.get(subject) : 0) + total
        );
      }
    }
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    for (Id subject : marked.keySet()) {
      Integer m = marked.get(subject);
      Integer a = attended.containsKey(subject) ? attended.get(subject) : 0;
      result.put(
        subject,
        m == 0 ? null : (Decimal.valueOf(a) * 100 / m).setScale(1)
      );
    }
    return result;
  }

  private static List<Subject_Result__c> resultsWhere(String field, Id value) {
    return Database.query(
      'SELECT Id, Section_Subject__c, Term__c, Attempt__c, Internal_Marks__c, Exam_Marks__c, Total_Marks__c, ' +
        'Max_Marks__c, Result__c, Status__c, Student__r.Name, Section_Subject__r.Subject__r.Name ' +
        'FROM Subject_Result__c WHERE ' +
        field +
        ' = :value ORDER BY Term__c, Section_Subject__r.Subject__r.Name, Attempt__c',
      AccessLevel.SYSTEM_MODE
    );
  }

  private static List<Subject_Result__c> resultsIn(Set<Id> sectionSubjectIds) {
    return [
      SELECT
        Id,
        Section_Subject__c,
        Term__c,
        Attempt__c,
        Internal_Marks__c,
        Exam_Marks__c,
        Total_Marks__c,
        Max_Marks__c,
        Result__c,
        Status__c,
        Student__r.Name,
        Section_Subject__r.Subject__r.Name
      FROM Subject_Result__c
      WHERE Section_Subject__c IN :sectionSubjectIds
      WITH SYSTEM_MODE
      ORDER BY Student__r.Name, Attempt__c
    ];
  }

  private static SubjectRow row(Subject_Result__c r) {
    SubjectRow row = new SubjectRow();
    row.id = r.Id;
    row.subject = r.Section_Subject__r.Subject__r.Name;
    row.term = r.Term__c;
    row.attempt = r.Attempt__c;
    row.internalMarks = r.Internal_Marks__c;
    row.examMarks = r.Exam_Marks__c;
    row.total = r.Total_Marks__c;
    row.max = r.Max_Marks__c;
    row.result = r.Result__c;
    row.status = r.Status__c;
    row.student = r.Student__r.Name;
    return row;
  }

  private static Option option(CourseOffering s) {
    Option o = new Option();
    o.value = s.Id;
    o.label =
      s.Name +
      ' · ' +
      s.Academic_Year__c +
      ' · ' +
      (s.Seats_Taken__c == null ? 0 : s.Seats_Taken__c.intValue()) +
      '/' +
      (s.EnrollmentCapacity == null
        ? '∞'
        : String.valueOf(s.EnrollmentCapacity));
    return o;
  }
}
