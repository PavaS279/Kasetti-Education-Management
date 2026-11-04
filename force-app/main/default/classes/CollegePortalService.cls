/**
 * Student-first college view for the portal: programme, roll number, section,
 * today's periods, attendance and results by subject, and fees due. Called by
 * PortalService.learnerFor only after the viewer's access to the learner has
 * been checked (ADR-003); marks are shown only once the Dean has finalised them.
 */
public without sharing class CollegePortalService {
  public class Period {
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public Datetime startsAt;
    @AuraEnabled
    public Datetime endsAt;
    @AuraEnabled
    public String room;
    @AuraEnabled
    public String faculty;
    @AuraEnabled
    public String status;
  }

  public class Subject {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Decimal term;
    @AuraEnabled
    public Decimal attempt;
    @AuraEnabled
    public Decimal attendancePercent;
    @AuraEnabled
    public Boolean published = false;
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
  }

  public class Term {
    @AuraEnabled
    public Decimal term;
    @AuraEnabled
    public String outcome;
    @AuraEnabled
    public Decimal percentage;
    @AuraEnabled
    public Decimal backlogs;
  }

  public class Summary {
    @AuraEnabled
    public String programme;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String campus;
    @AuraEnabled
    public String rollNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String academicYear;
    @AuraEnabled
    public Decimal yearOfStudy;
    @AuraEnabled
    public String section;
    @AuraEnabled
    public Date joiningDate;
    @AuraEnabled
    public Date paymentDueBy;
    @AuraEnabled
    public Decimal feesDue = 0;
    @AuraEnabled
    public Integer openBacklogs = 0;
    @AuraEnabled
    public List<Period> today = new List<Period>();
    @AuraEnabled
    public List<Subject> subjects = new List<Subject>();
    @AuraEnabled
    public List<Term> terms = new List<Term>();
  }

  /** The learner's current college programme, or null when they have none. */
  public static Summary summaryFor(Id learnerContactId) {
    List<Programme_Enrolment__c> enrolments = [
      SELECT
        Id,
        Status__c,
        Roll_Number__c,
        Academic_Year__c,
        Current_Year_Of_Study__c,
        Joining_Date__c,
        Payment_Due_By__c,
        Programme__r.Name,
        Branch__r.Name,
        Campus__r.Name
      FROM Programme_Enrolment__c
      WHERE
        Student__r.PersonContactId = :learnerContactId
        AND Status__c IN (
          'Provisional',
          'Enrolled',
          'Completed',
          'Discontinued'
        )
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (enrolments.isEmpty()) {
      return null;
    }
    Programme_Enrolment__c e = enrolments[0];
    Summary s = new Summary();
    s.programme = e.Programme__r.Name;
    s.branch = e.Branch__r.Name;
    s.campus = e.Campus__r.Name;
    s.rollNumber = e.Roll_Number__c;
    s.status = e.Status__c;
    s.academicYear = e.Academic_Year__c;
    s.yearOfStudy = e.Current_Year_Of_Study__c;
    s.joiningDate = e.Joining_Date__c;
    s.paymentDueBy = e.Status__c == 'Provisional' ? e.Payment_Due_By__c : null;
    s.feesDue = (Decimal) [
        SELECT SUM(Balance_Due__c) due
        FROM Student_Invoice__c
        WHERE
          Programme_Enrolment__c = :e.Id
          AND Status__c IN :BillingService.OPEN_STATUSES
        WITH SYSTEM_MODE
      ][0]
      .get('due');
    s.feesDue = s.feesDue == null ? 0 : s.feesDue;

    List<CourseOfferingParticipant> sections = [
      SELECT Id, CourseOfferingId, CourseOffering.Name, Academic_Year__c
      FROM CourseOfferingParticipant
      WHERE Programme_Enrolment__c = :e.Id
      WITH SYSTEM_MODE
      ORDER BY Academic_Year__c DESC, Year_Of_Study__c DESC
      LIMIT 1
    ];
    if (!sections.isEmpty()) {
      CourseOfferingParticipant current = sections[0];
      s.section = current.CourseOffering.Name;
      s.academicYear = current.Academic_Year__c;
      Datetime dayStart = Datetime.newInstance(
        Date.today(),
        Time.newInstance(0, 0, 0, 0)
      );
      for (Class_Session__c p : [
        SELECT
          Start__c,
          End__c,
          Status__c,
          Room__r.Name,
          Teacher_User__r.Name,
          Section_Subject__r.Subject__r.Name
        FROM Class_Session__c
        WHERE
          Course_Offering__c = :current.CourseOfferingId
          AND Start__c >= :dayStart
          AND Start__c < :dayStart.addDays(1)
        WITH SYSTEM_MODE
        ORDER BY Start__c
        LIMIT 20
      ]) {
        Period period = new Period();
        period.subject = p.Section_Subject__r?.Subject__r?.Name;
        period.startsAt = p.Start__c;
        period.endsAt = p.End__c;
        period.room = p.Room__r?.Name;
        period.faculty = p.Teacher_User__r?.Name;
        period.status = p.Status__c;
        s.today.add(period);
      }
      Map<Id, Decimal> attendance = CollegeAcademicController.subjectAttendance(
        current.Id
      );
      for (Subject_Result__c r : [
        SELECT
          Section_Subject__c,
          Term__c,
          Attempt__c,
          Status__c,
          Result__c,
          Internal_Marks__c,
          Exam_Marks__c,
          Total_Marks__c,
          Max_Marks__c,
          Section_Subject__r.Subject__r.Name
        FROM Subject_Result__c
        WHERE Section_Enrolment__c = :current.Id
        WITH SYSTEM_MODE
        ORDER BY Term__c, Section_Subject__r.Subject__r.Name, Attempt__c
      ]) {
        Subject row = new Subject();
        row.name = r.Section_Subject__r.Subject__r.Name;
        row.term = r.Term__c;
        row.attempt = r.Attempt__c;
        row.attendancePercent = attendance.get(r.Section_Subject__c);
        // Draft and reopened marks are never shown to students or parents.
        row.published = r.Status__c == ResultService.FINAL_STATUS;
        if (row.published) {
          row.internalMarks = r.Internal_Marks__c;
          row.examMarks = r.Exam_Marks__c;
          row.total = r.Total_Marks__c;
          row.max = r.Max_Marks__c;
          row.result = r.Result__c;
        }
        s.subjects.add(row);
      }
    }
    for (Term_Result__c t : [
      SELECT Term__c, Outcome__c, Percentage__c, Backlogs__c
      FROM Term_Result__c
      WHERE
        Programme_Enrolment__c = :e.Id
        AND Status__c = :ResultService.FINAL_STATUS
      WITH SYSTEM_MODE
      ORDER BY Term__c
    ]) {
      Term row = new Term();
      row.term = t.Term__c;
      row.outcome = t.Outcome__c;
      row.percentage = t.Percentage__c;
      row.backlogs = t.Backlogs__c;
      s.terms.add(row);
    }
    s.openBacklogs = ResultService.openBacklogs(e.Id).size();
    return s;
  }
}
