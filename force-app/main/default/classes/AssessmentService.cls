/**
 * Assessments and results: gradebook, draft scores, and publication.
 *
 * Who may enter results: the class teacher, or anyone who can edit the
 * assessment (academic coordinators, branch managers, administrators).
 * Results are written without sharing after that check, because teachers
 * only read classes and enrolments. Publishing fixes each result's grade from
 * Grade_Band__mdt; published results are locked.
 */
public with sharing class AssessmentService {
  public static final String DEFAULT_SCALE = 'Standard';

  public class ResultRow {
    @AuraEnabled
    public Id learnerContactId { get; set; }
    @AuraEnabled
    public Id enrolmentId { get; set; }
    @AuraEnabled
    public String learnerName { get; set; }
    @AuraEnabled
    public Decimal score { get; set; }
    @AuraEnabled
    public Boolean absent { get; set; }
    @AuraEnabled
    public String feedback { get; set; }
    @AuraEnabled
    public String grade { get; set; }
  }

  public class Band {
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public Decimal minPercent;
  }

  public class Gradebook {
    @AuraEnabled
    public Course_Assessment__c assessment;
    @AuraEnabled
    public List<ResultRow> rows = new List<ResultRow>();
    @AuraEnabled
    public List<Band> bands = new List<Band>();
    @AuraEnabled
    public Boolean canEdit;
  }

  public static Gradebook getGradebook(Id assessmentId) {
    Gradebook book = new Gradebook();
    book.assessment = load(assessmentId);
    book.canEdit =
      canEdit(book.assessment) && book.assessment.Status__c == 'Draft';
    book.bands = bands(book.assessment.Grade_Scale__c);
    Map<Id, Assessment_Result__c> existing = new Map<Id, Assessment_Result__c>();
    for (Assessment_Result__c r : [
      SELECT Learner__c, Score__c, Absent__c, Feedback__c, Grade__c
      FROM Assessment_Result__c
      WHERE Course_Assessment__c = :assessmentId
      WITH SYSTEM_MODE
    ]) {
      existing.put(r.Learner__c, r);
    }
    for (CourseOfferingParticipant e : [
      SELECT Id, ParticipantContactId, ParticipantContact.Name
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :book.assessment.Course_Offering__c
        AND ParticipantAffiliation = 'Student'
        AND (ParticipationStatus IN :SeatService.SEAT_STATUSES
        OR ParticipationStatus = 'Completed'
        OR ParticipantContactId IN :existing.keySet())
      WITH SYSTEM_MODE
      ORDER BY ParticipantContact.Name
    ]) {
      Assessment_Result__c r = existing.get(e.ParticipantContactId);
      ResultRow row = new ResultRow();
      row.learnerContactId = e.ParticipantContactId;
      row.enrolmentId = e.Id;
      row.learnerName = e.ParticipantContact.Name;
      row.score = r == null ? null : r.Score__c;
      row.absent = r == null ? false : r.Absent__c;
      row.feedback = r == null ? null : r.Feedback__c;
      row.grade = r == null ? null : r.Grade__c;
      book.rows.add(row);
    }
    return book;
  }

  public static void saveResults(Id assessmentId, List<ResultRow> rows) {
    Course_Assessment__c assessment = load(assessmentId);
    assertEditable(assessment);
    List<Assessment_Result__c> upserts = new List<Assessment_Result__c>();
    Set<Id> existing = new Set<Id>();
    for (Assessment_Result__c r : [
      SELECT Learner__c
      FROM Assessment_Result__c
      WHERE Course_Assessment__c = :assessmentId
      WITH SYSTEM_MODE
    ]) {
      existing.add(r.Learner__c);
    }
    for (ResultRow row : rows) {
      Boolean absent = row.absent == true;
      if (row.score == null && !absent && String.isBlank(row.feedback)) {
        continue;
      }
      if (
        !absent &&
        row.score != null &&
        (row.score < 0 ||
        row.score > assessment.Max_Score__c)
      ) {
        throw new AppException(
          row.learnerName +
            ': score must be between 0 and ' +
            assessment.Max_Score__c.stripTrailingZeros().toPlainString() +
            '.'
        );
      }
      Assessment_Result__c result = new Assessment_Result__c(
        Unique_Key__c = assessmentId + ':' + row.learnerContactId,
        Learner__c = row.learnerContactId,
        Enrolment__c = row.enrolmentId,
        Score__c = absent ? null : row.score,
        Max_Score__c = assessment.Max_Score__c,
        Absent__c = absent,
        Feedback__c = row.feedback,
        Status__c = 'Draft',
        Entered_By__c = UserInfo.getUserId()
      );
      if (!existing.contains(row.learnerContactId)) {
        result.Course_Assessment__c = assessmentId;
      }
      upserts.add(result);
    }
    if (upserts.isEmpty()) {
      throw new AppException('Enter at least one score.');
    }
    new Writer().upsertResults(upserts);
  }

  /** Publishes results: grades are calculated now and kept even if bands change later. */
  public static void publish(Id assessmentId) {
    Course_Assessment__c assessment = load(assessmentId);
    assertEditable(assessment);
    List<Band> scale = bands(assessment.Grade_Scale__c);
    List<Assessment_Result__c> results = [
      SELECT Id, Score__c, Max_Score__c, Absent__c
      FROM Assessment_Result__c
      WHERE Course_Assessment__c = :assessmentId
      WITH SYSTEM_MODE
    ];
    if (results.isEmpty()) {
      throw new AppException('Enter results before publishing.');
    }
    Decimal total = 0;
    Integer graded = 0;
    for (Assessment_Result__c r : results) {
      if (r.Absent__c || r.Score__c == null) {
        r.Grade__c = r.Absent__c ? 'ABS' : null;
      } else {
        Decimal pct = r.Score__c / r.Max_Score__c * 100;
        r.Grade__c = gradeFor(pct, scale);
        total += pct;
        graded++;
      }
      r.Status__c = 'Published';
    }
    Writer writer = new Writer();
    writer.updateRecords(results);
    writer.updateRecords(
      new List<SObject>{
        new Course_Assessment__c(
          Id = assessmentId,
          Status__c = 'Published',
          Published_On__c = System.now(),
          Published_By__c = UserInfo.getUserId(),
          Average_Percentage__c = graded == 0
            ? null
            : (total / graded).setScale(2)
        )
      }
    );
  }

  public static String gradeFor(Decimal percent, List<Band> scale) {
    for (Band band : scale) {
      if (percent >= band.minPercent) {
        return band.grade;
      }
    }
    return null;
  }

  /** Bands for a scale, highest minimum first. */
  public static List<Band> bands(String scale) {
    String name = String.isBlank(scale) ? DEFAULT_SCALE : scale;
    List<Band> result = new List<Band>();
    // Read from the metadata cache (no SOQL): SOQL with binds on custom metadata
    // fails in this org's user-mode context ("Variable does not exist: tmpVar1").
    for (Grade_Band__mdt row : Grade_Band__mdt.getAll().values()) {
      if (row.Scale__c != name || row.Min_Percent__c == null) {
        continue;
      }
      Band band = new Band();
      band.grade = row.Grade__c;
      band.minPercent = row.Min_Percent__c;
      Integer index = 0;
      while (
        index < result.size() &&
        result[index].minPercent >= band.minPercent
      ) {
        index++;
      }
      if (index == result.size()) {
        result.add(band);
      } else {
        result.add(index, band);
      }
    }
    if (result.isEmpty()) {
      throw new AppException('Grade scale ' + name + ' has no grade bands.');
    }
    return result;
  }

  /** Published results of a learner, newest first (for Learner 360 and the portal). */
  public static List<Assessment_Result__c> publishedResults(
    Id learnerContactId
  ) {
    return [
      SELECT
        Id,
        Score__c,
        Max_Score__c,
        Percentage__c,
        Grade__c,
        Absent__c,
        Feedback__c,
        Course_Assessment__r.Name,
        Course_Assessment__r.Assessment_Type__c,
        Course_Assessment__r.Assessment_Date__c,
        Course_Assessment__r.Course_Offering__r.Name
      FROM Assessment_Result__c
      WHERE Learner__c = :learnerContactId AND Status__c = 'Published'
      WITH SYSTEM_MODE
      ORDER BY Course_Assessment__r.Assessment_Date__c DESC NULLS LAST
      LIMIT 200
    ];
  }

  @TestVisible
  private static Boolean canEdit(Course_Assessment__c assessment) {
    if (assessment.Course_Offering__r.Teacher_User__c == UserInfo.getUserId()) {
      return true;
    }
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :assessment.Id
    ];
    return !access.isEmpty() && access[0].HasEditAccess;
  }

  private static void assertEditable(Course_Assessment__c assessment) {
    if (!canEdit(assessment)) {
      throw new AppException(
        'Only the class teacher or an academic coordinator can enter or publish results.'
      );
    }
    if (assessment.Status__c != 'Draft') {
      throw new AppException('Published results are locked.');
    }
  }

  private static Course_Assessment__c load(Id assessmentId) {
    List<Course_Assessment__c> rows = [
      SELECT
        Id,
        Name,
        Course_Offering__c,
        Course_Offering__r.Name,
        Course_Offering__r.Teacher_User__c,
        Assessment_Type__c,
        Max_Score__c,
        Weight__c,
        Assessment_Date__c,
        Grade_Scale__c,
        Status__c,
        Published_On__c,
        Average_Percentage__c
      FROM Course_Assessment__c
      WHERE Id = :assessmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Assessment not found or not accessible.');
    }
    return rows[0];
  }

  /** Writes authorised by the teacher-or-editor rule above, not by record ownership. */
  private without sharing class Writer {
    void upsertResults(List<Assessment_Result__c> results) {
      Database.upsert(
        results,
        Assessment_Result__c.Unique_Key__c,
        AccessLevel.SYSTEM_MODE
      );
    }

    void updateRecords(List<SObject> records) {
      Database.update(records, AccessLevel.SYSTEM_MODE);
    }
  }
}
