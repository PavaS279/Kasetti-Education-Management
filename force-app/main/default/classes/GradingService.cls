/**
 * Course grades and report cards (F2.7).
 *
 * The course score of an enrolment is the weighted average of the percentages
 * the learner achieved in the class's published assessments. Assessment
 * Weight__c sets each one's share; when no assessment has a weight they count
 * equally, and when some do, unweighted ones do not count. Absence counts as 0%
 * (Education Setting Absent_Counts_As_Zero) or is left out; assessments without
 * a result for the learner are left out and the remaining weights rescaled. The
 * grade comes from the class's grade scale (Grade_Band__mdt).
 *
 * Grades are provisional and recalculated whenever an assessment is published.
 * Finalising locks them, issues a report card PDF per learner and tells each
 * family (F2.5). Reopening makes them provisional again and marks the issued
 * report cards superseded so that finalising again issues new ones.
 */
public with sharing class GradingService {
  public static final String PROVISIONAL = 'Provisional';
  public static final String FINAL_STATUS = 'Final';
  public static final Set<String> GRADED_STATUSES = new Set<String>{
    'Enrolled',
    'On Hold',
    'Completed'
  };

  public class Column {
    @AuraEnabled
    public Id assessmentId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String assessmentType;
    @AuraEnabled
    public Date assessmentDate;
    @AuraEnabled
    public Decimal weight;
    /** Share of the course grade after normalising (percent). */
    @AuraEnabled
    public Decimal share;
    @AuraEnabled
    public Boolean published;
  }

  public class Cell {
    @AuraEnabled
    public Id assessmentId;
    @AuraEnabled
    public Decimal percent;
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public Boolean absent;
  }

  public class Row {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learnerName;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public Integer graded;
    @AuraEnabled
    public Decimal attendance;
    @AuraEnabled
    public String comment;
    @AuraEnabled
    public Id reportCardId;
    @AuraEnabled
    public List<Cell> cells = new List<Cell>();
  }

  public class ClassGrades {
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime finalisedOn;
    @AuraEnabled
    public String finalisedBy;
    @AuraEnabled
    public String scale;
    @AuraEnabled
    public Boolean equalWeights;
    @AuraEnabled
    public Integer draftAssessments = 0;
    @AuraEnabled
    public Decimal classAverage;
    @AuraEnabled
    public List<Column> columns = new List<Column>();
    @AuraEnabled
    public List<Row> rows = new List<Row>();
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public Boolean canReopen;
  }

  public class CommentRow {
    @AuraEnabled
    public Id enrolmentId { get; set; }
    @AuraEnabled
    public String comment { get; set; }
  }

  public class WeightRow {
    @AuraEnabled
    public Id assessmentId { get; set; }
    @AuraEnabled
    public Decimal weight { get; set; }
  }

  // ----------------------------------------------------------- calculation

  /** Recalculates provisional course grades of the classes (final grades are left alone). */
  public static void calculate(Set<Id> offeringIds) {
    offeringIds.remove(null);
    if (offeringIds.isEmpty()) {
      return;
    }
    Map<Id, CourseOffering> offerings = new Map<Id, CourseOffering>(
      [
        SELECT Id, Grading_Status__c
        FROM CourseOffering
        WHERE Id IN :offeringIds
        WITH SYSTEM_MODE
      ]
    );
    Set<Id> open = new Set<Id>();
    for (CourseOffering offering : offerings.values()) {
      if (offering.Grading_Status__c != FINAL_STATUS) {
        open.add(offering.Id);
      }
    }
    if (open.isEmpty()) {
      return;
    }
    List<CourseOfferingParticipant> updates = new List<CourseOfferingParticipant>();
    for (Id offeringId : open) {
      Model model = new Model(offeringId);
      for (CourseOfferingParticipant enrolment : model.enrolments) {
        Outcome outcome = model.outcomeFor(enrolment.Id);
        updates.add(
          new CourseOfferingParticipant(
            Id = enrolment.Id,
            Course_Score__c = outcome.score,
            Course_Grade__c = outcome.grade,
            Graded_Assessments__c = outcome.graded,
            Grade_Status__c = PROVISIONAL,
            Grades_Calculated_On__c = System.now()
          )
        );
      }
    }
    new Writer().updateRecords(updates);
  }

  // -------------------------------------------------------------- actions

  /** Class gradebook: weights, every learner's results, course score and grade. */
  public static ClassGrades classGrades(Id offeringId) {
    CourseOffering offering = loadOffering(offeringId);
    Model model = new Model(offeringId);
    ClassGrades result = new ClassGrades();
    result.className = offering.Name;
    result.status = offering.Grading_Status__c == FINAL_STATUS
      ? FINAL_STATUS
      : 'Open';
    result.finalisedOn = offering.Grades_Finalised_On__c;
    result.finalisedBy = offering.Grades_Finalised_By__r?.Name;
    result.scale = model.scaleName;
    result.equalWeights = !model.weighted;
    result.canEdit = canEdit(offering);
    result.canReopen = canReopen(offering);
    for (Course_Assessment__c assessment : model.allAssessments) {
      Column column = new Column();
      column.assessmentId = assessment.Id;
      column.name = assessment.Name;
      column.assessmentType = assessment.Assessment_Type__c;
      column.assessmentDate = assessment.Assessment_Date__c;
      column.weight = assessment.Weight__c;
      column.published = assessment.Status__c == 'Published';
      column.share = model.share(assessment.Id);
      if (!column.published) {
        result.draftAssessments++;
      }
      result.columns.add(column);
    }
    Map<Id, Id> reportCards = reportCards(model.enrolmentIds());
    Decimal total = 0;
    Integer counted = 0;
    for (CourseOfferingParticipant enrolment : model.enrolments) {
      Row row = new Row();
      row.enrolmentId = enrolment.Id;
      row.learnerAccountId = enrolment.ParticipantAccountId;
      row.learnerName = enrolment.ParticipantContact.Name;
      row.attendance = enrolment.Attendance_Rate__c;
      row.comment = enrolment.Report_Comment__c;
      row.reportCardId = reportCards.get(enrolment.Id);
      Outcome outcome = model.outcomeFor(enrolment.Id);
      row.score = outcome.score;
      row.grade = outcome.grade;
      row.graded = outcome.graded;
      if (result.status == FINAL_STATUS) {
        // Final grades are shown as issued, even if bands or results changed.
        row.score = enrolment.Course_Score__c;
        row.grade = enrolment.Course_Grade__c;
      }
      for (Course_Assessment__c assessment : model.allAssessments) {
        Cell cell = new Cell();
        cell.assessmentId = assessment.Id;
        Assessment_Result__c r = model.result(enrolment.Id, assessment.Id);
        if (r != null && assessment.Status__c == 'Published') {
          cell.absent = r.Absent__c;
          cell.percent = model.percent(r);
          cell.grade = r.Grade__c;
        }
        row.cells.add(cell);
      }
      if (row.score != null) {
        total += row.score;
        counted++;
      }
      result.rows.add(row);
    }
    result.classAverage = counted == 0 ? null : (total / counted).setScale(1);
    return result;
  }

  /** Sets assessment weights (percent). Blank weights count equally only when all are blank. */
  public static void saveWeights(Id offeringId, List<WeightRow> weights) {
    CourseOffering offering = loadOffering(offeringId);
    assertOpenAndEditable(offering);
    Set<Id> ids = new Set<Id>();
    for (WeightRow w : weights) {
      if (w.weight != null && (w.weight < 0 || w.weight > 100)) {
        throw new AppException('Weights must be between 0 and 100.');
      }
      ids.add(w.assessmentId);
    }
    Map<Id, Course_Assessment__c> owned = new Map<Id, Course_Assessment__c>(
      [
        SELECT Id
        FROM Course_Assessment__c
        WHERE Id IN :ids AND Course_Offering__c = :offeringId
        WITH SYSTEM_MODE
      ]
    );
    List<Course_Assessment__c> updates = new List<Course_Assessment__c>();
    for (WeightRow w : weights) {
      if (!owned.containsKey(w.assessmentId)) {
        throw new AppException('An assessment does not belong to this class.');
      }
      updates.add(
        new Course_Assessment__c(Id = w.assessmentId, Weight__c = w.weight)
      );
    }
    new Writer().updateRecords(updates);
    calculate(new Set<Id>{ offeringId });
  }

  /** Saves report card comments. */
  public static void saveComments(Id offeringId, List<CommentRow> comments) {
    CourseOffering offering = loadOffering(offeringId);
    assertOpenAndEditable(offering);
    Set<Id> enrolled = new Map<Id, CourseOfferingParticipant>(
        [
          SELECT Id
          FROM CourseOfferingParticipant
          WHERE CourseOfferingId = :offeringId
          WITH SYSTEM_MODE
        ]
      )
      .keySet();
    List<CourseOfferingParticipant> updates = new List<CourseOfferingParticipant>();
    for (CommentRow c : comments) {
      if (!enrolled.contains(c.enrolmentId)) {
        throw new AppException('A learner is not enrolled in this class.');
      }
      updates.add(
        new CourseOfferingParticipant(
          Id = c.enrolmentId,
          Report_Comment__c = String.isBlank(c.comment)
            ? null
            : c.comment.trim().left(2000)
        )
      );
    }
    new Writer().updateRecords(updates);
  }

  /** Locks the grades, issues report cards and notifies families. */
  public static Integer finalise(Id offeringId) {
    CourseOffering offering = loadOffering(offeringId);
    assertOpenAndEditable(offering);
    Model model = new Model(offeringId);
    if (model.allAssessments.isEmpty()) {
      throw new AppException(
        'Add and publish assessments before finalising grades.'
      );
    }
    for (Course_Assessment__c assessment : model.allAssessments) {
      if (assessment.Status__c != 'Published') {
        throw new AppException(
          'Publish or delete the draft assessment "' +
            assessment.Name +
            '" before finalising grades.'
        );
      }
    }
    if (model.enrolments.isEmpty()) {
      throw new AppException('There are no learners to grade in this class.');
    }
    List<SObject> updates = new List<SObject>();
    Set<Id> enrolmentIds = new Set<Id>();
    for (CourseOfferingParticipant enrolment : model.enrolments) {
      Outcome outcome = model.outcomeFor(enrolment.Id);
      updates.add(
        new CourseOfferingParticipant(
          Id = enrolment.Id,
          Course_Score__c = outcome.score,
          Course_Grade__c = outcome.grade,
          Graded_Assessments__c = outcome.graded,
          Grade_Status__c = FINAL_STATUS,
          Grades_Calculated_On__c = System.now()
        )
      );
      enrolmentIds.add(enrolment.Id);
    }
    updates.add(
      new CourseOffering(
        Id = offeringId,
        Grading_Status__c = FINAL_STATUS,
        Grades_Finalised_On__c = System.now(),
        Grades_Finalised_By__c = UserInfo.getUserId()
      )
    );
    new Writer().updateRecords(updates);
    DocumentService.enqueue(enrolmentIds, DocumentService.REPORT_CARD);
    MessageService.reportCardsReady(enrolmentIds);
    return enrolmentIds.size();
  }

  /** Makes final grades provisional again; issued report cards are marked superseded. */
  public static void reopen(Id offeringId, String reason) {
    if (String.isBlank(reason)) {
      throw new AppException('Enter why the grades are being reopened.');
    }
    CourseOffering offering = loadOffering(offeringId);
    if (!canReopen(offering)) {
      throw new AppException(
        'Only coordinators and administrators can reopen final grades.'
      );
    }
    if (offering.Grading_Status__c != FINAL_STATUS) {
      throw new AppException('The grades of this class are not final.');
    }
    List<CourseOfferingParticipant> enrolments = [
      SELECT Id
      FROM CourseOfferingParticipant
      WHERE CourseOfferingId = :offeringId AND Grade_Status__c = :FINAL_STATUS
      WITH SYSTEM_MODE
    ];
    List<SObject> updates = new List<SObject>();
    for (CourseOfferingParticipant enrolment : enrolments) {
      updates.add(
        new CourseOfferingParticipant(
          Id = enrolment.Id,
          Grade_Status__c = PROVISIONAL
        )
      );
    }
    updates.add(
      new CourseOffering(
        Id = offeringId,
        Grading_Status__c = 'Open',
        Grades_Finalised_On__c = null,
        Grades_Finalised_By__c = null
      )
    );
    Writer writer = new Writer();
    writer.updateRecords(updates);
    DocumentService.supersede(
      new Map<Id, CourseOfferingParticipant>(enrolments).keySet(),
      DocumentService.REPORT_CARD,
      reason
    );
    calculate(new Set<Id>{ offeringId });
  }

  // ----------------------------------------------------------- report card

  /** One line of a report card. Properties (not fields) so Visualforce can bind to them. */
  public class ReportLine {
    public String name { get; private set; }
    public String assessmentType { get; private set; }
    public Date assessmentDate { get; private set; }
    public Decimal share { get; private set; }
    public String result { get; private set; }
    public Decimal percent { get; private set; }
    public String grade { get; private set; }
    public String feedback { get; private set; }
  }

  public class ReportBand {
    public String grade { get; private set; }
    public Decimal minPercent { get; private set; }
  }

  public class ReportCard {
    public String learnerName { get; private set; }
    public String className { get; private set; }
    public String courseName { get; private set; }
    public String teacherName { get; private set; }
    public Date startDate { get; private set; }
    public Date endDate { get; private set; }
    public Decimal score { get; private set; }
    public String grade { get; private set; }
    public String status { get; private set; }
    public Decimal attendance { get; private set; }
    public String comment { get; private set; }
    public String scale { get; private set; }
    public Boolean equalWeights { get; private set; }
    public Id branchId { get; private set; }
    public List<ReportLine> lines { get; private set; }
    public List<ReportBand> bands { get; private set; }
  }

  /** Report card content for one enrolment (the caller must be able to read it). */
  public static ReportCard reportCard(Id enrolmentId) {
    List<CourseOfferingParticipant> rows = [
      SELECT
        Id,
        CourseOfferingId,
        CourseOffering.Name,
        CourseOffering.LearningCourse.Name,
        CourseOffering.Teacher_User__r.Name,
        CourseOffering.Branch__c,
        ParticipantContact.Name,
        StartDate,
        EndDate,
        Course_Score__c,
        Course_Grade__c,
        Grade_Status__c,
        Attendance_Rate__c,
        Report_Comment__c
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Enrolment not found or not accessible.');
    }
    CourseOfferingParticipant enrolment = rows[0];
    Model model = new Model(enrolment.CourseOfferingId);
    ReportCard card = new ReportCard();
    card.learnerName = enrolment.ParticipantContact.Name;
    card.className = enrolment.CourseOffering.Name;
    card.courseName = enrolment.CourseOffering.LearningCourse?.Name;
    card.teacherName = enrolment.CourseOffering.Teacher_User__r?.Name;
    card.branchId = enrolment.CourseOffering.Branch__c;
    card.startDate = enrolment.StartDate;
    card.endDate = enrolment.EndDate;
    card.status = enrolment.Grade_Status__c;
    card.attendance = enrolment.Attendance_Rate__c;
    card.comment = enrolment.Report_Comment__c;
    card.scale = model.scaleName;
    card.equalWeights = !model.weighted;
    if (enrolment.Grade_Status__c == FINAL_STATUS) {
      card.score = enrolment.Course_Score__c;
      card.grade = enrolment.Course_Grade__c;
    } else {
      Outcome outcome = model.outcomeFor(enrolment.Id);
      card.score = outcome.score;
      card.grade = outcome.grade;
    }
    card.lines = new List<ReportLine>();
    for (Course_Assessment__c a : model.published) {
      ReportLine line = new ReportLine();
      line.name = a.Name;
      line.assessmentType = a.Assessment_Type__c;
      line.assessmentDate = a.Assessment_Date__c;
      line.share = model.share(a.Id);
      Assessment_Result__c r = model.result(enrolment.Id, a.Id);
      if (r == null) {
        line.result = 'Not taken';
      } else if (r.Absent__c) {
        line.result = 'Absent';
        line.percent = model.percent(r);
      } else {
        line.result =
          r.Score__c?.stripTrailingZeros().toPlainString() +
          ' / ' +
          r.Max_Score__c?.stripTrailingZeros().toPlainString();
        line.percent = model.percent(r);
        line.grade = r.Grade__c;
        line.feedback = r.Feedback__c;
      }
      card.lines.add(line);
    }
    card.bands = new List<ReportBand>();
    for (AssessmentService.Band b : model.bands) {
      ReportBand band = new ReportBand();
      band.grade = b.grade;
      band.minPercent = b.minPercent;
      card.bands.add(band);
    }
    return card;
  }

  // ---------------------------------------------------------------- model

  public class Outcome {
    public Decimal score;
    public String grade;
    public Integer graded = 0;
  }

  /** Assessments, results and weights of one class, loaded once. */
  private class Model {
    List<Course_Assessment__c> allAssessments = new List<Course_Assessment__c>();
    List<Course_Assessment__c> published = new List<Course_Assessment__c>();
    List<CourseOfferingParticipant> enrolments;
    Map<String, Assessment_Result__c> results = new Map<String, Assessment_Result__c>();
    Boolean weighted = false;
    Boolean absentIsZero;
    String scaleName;
    List<AssessmentService.Band> bands;

    Model(Id offeringId) {
      absentIsZero = AppSettings.getBoolean('Absent_Counts_As_Zero', true);
      allAssessments = [
        SELECT
          Id,
          Name,
          Assessment_Type__c,
          Assessment_Date__c,
          Max_Score__c,
          Weight__c,
          Status__c,
          Grade_Scale__c
        FROM Course_Assessment__c
        WHERE Course_Offering__c = :offeringId
        WITH SYSTEM_MODE
        ORDER BY Assessment_Date__c NULLS LAST, Name
      ];
      for (Course_Assessment__c a : allAssessments) {
        if (a.Status__c == 'Published') {
          published.add(a);
          weighted |= a.Weight__c != null && a.Weight__c > 0;
          if (scaleName == null && String.isNotBlank(a.Grade_Scale__c)) {
            scaleName = a.Grade_Scale__c;
          }
        }
      }
      scaleName = scaleName == null
        ? AssessmentService.DEFAULT_SCALE
        : scaleName;
      bands = AssessmentService.bands(scaleName);
      enrolments = [
        SELECT
          Id,
          ParticipantAccountId,
          ParticipantContactId,
          ParticipantContact.Name,
          Attendance_Rate__c,
          Report_Comment__c,
          Course_Score__c,
          Course_Grade__c
        FROM CourseOfferingParticipant
        WHERE
          CourseOfferingId = :offeringId
          AND ParticipationStatus IN :GRADED_STATUSES
        WITH SYSTEM_MODE
        ORDER BY ParticipantContact.LastName, ParticipantContact.FirstName
      ];
      if (!allAssessments.isEmpty()) {
        for (Assessment_Result__c r : [
          SELECT
            Course_Assessment__c,
            Enrolment__c,
            Learner__c,
            Score__c,
            Max_Score__c,
            Absent__c,
            Grade__c,
            Feedback__c
          FROM Assessment_Result__c
          WHERE
            Course_Assessment__c IN :new Map<Id, Course_Assessment__c>(
                allAssessments
              )
              .keySet()
          WITH SYSTEM_MODE
        ]) {
          results.put(r.Enrolment__c + '|' + r.Course_Assessment__c, r);
        }
      }
    }

    Set<Id> enrolmentIds() {
      return new Map<Id, CourseOfferingParticipant>(enrolments).keySet();
    }

    Assessment_Result__c result(Id enrolmentId, Id assessmentId) {
      return results.get(enrolmentId + '|' + assessmentId);
    }

    Decimal weightOf(Course_Assessment__c a) {
      if (!weighted) {
        return 1;
      }
      return a.Weight__c == null ? 0 : a.Weight__c;
    }

    /** Normalised share of the course grade (percent), for published assessments. */
    Decimal share(Id assessmentId) {
      Decimal total = 0;
      Decimal mine;
      for (Course_Assessment__c a : published) {
        total += weightOf(a);
        if (a.Id == assessmentId) {
          mine = weightOf(a);
        }
      }
      return mine == null ||
        total == 0
        ? null
        : (mine / total * 100).setScale(1);
    }

    Decimal percent(Assessment_Result__c r) {
      if (r.Absent__c) {
        return absentIsZero ? 0 : null;
      }
      if (r.Score__c == null || r.Max_Score__c == null || r.Max_Score__c == 0) {
        return null;
      }
      return (r.Score__c / r.Max_Score__c * 100).setScale(2);
    }

    Outcome outcomeFor(Id enrolmentId) {
      Outcome outcome = new Outcome();
      Decimal weightTotal = 0;
      Decimal sum = 0;
      for (Course_Assessment__c a : published) {
        Decimal weight = weightOf(a);
        Assessment_Result__c r = result(enrolmentId, a.Id);
        if (weight == 0 || r == null) {
          continue;
        }
        Decimal pct = percent(r);
        if (pct == null) {
          continue;
        }
        sum += pct * weight;
        weightTotal += weight;
        outcome.graded++;
      }
      if (weightTotal > 0) {
        outcome.score = (sum / weightTotal).setScale(2);
        outcome.grade = AssessmentService.gradeFor(outcome.score, bands);
      }
      return outcome;
    }
  }

  // --------------------------------------------------------------- helpers

  private static Map<Id, Id> reportCards(Set<Id> enrolmentIds) {
    Map<Id, Id> result = new Map<Id, Id>();
    if (enrolmentIds.isEmpty()) {
      return result;
    }
    String marker = 'KEM ' + DocumentService.REPORT_CARD;
    for (ContentDocumentLink link : [
      SELECT
        LinkedEntityId,
        ContentDocumentId,
        ContentDocument.LatestPublishedVersion.Description
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :enrolmentIds
      WITH SYSTEM_MODE
    ]) {
      if (link.ContentDocument.LatestPublishedVersion.Description == marker) {
        result.put(link.LinkedEntityId, link.ContentDocumentId);
      }
    }
    return result;
  }

  private static CourseOffering loadOffering(Id offeringId) {
    List<CourseOffering> rows = [
      SELECT
        Id,
        Name,
        Teacher_User__c,
        Grading_Status__c,
        Grades_Finalised_On__c,
        Grades_Finalised_By__r.Name
      FROM CourseOffering
      WHERE Id = :offeringId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Class not found or not accessible.');
    }
    return rows[0];
  }

  /** The class teacher, or anyone who can edit assessments of the class. */
  private static Boolean canEdit(CourseOffering offering) {
    if (offering.Teacher_User__c == UserInfo.getUserId()) {
      return true;
    }
    return canReopen(offering);
  }

  /**
   * Reopening final grades: edit access to the class, or Modify All on
   * assessments (administrators and academic coordinators).
   */
  private static Boolean canReopen(CourseOffering offering) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :offering.Id
    ];
    if (!access.isEmpty() && access[0].HasEditAccess) {
      return true;
    }
    return [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSetId IN (
            SELECT ParentId
            FROM ObjectPermissions
            WHERE
              SobjectType = 'Course_Assessment__c'
              AND PermissionsModifyAllRecords = TRUE
          )
      ] > 0;
  }

  private static void assertOpenAndEditable(CourseOffering offering) {
    if (!canEdit(offering)) {
      throw new AppException(
        'Only the class teacher or a coordinator can change grades of this class.'
      );
    }
    if (offering.Grading_Status__c == FINAL_STATUS) {
      throw new AppException(
        'Grades are final. Reopen them before making changes.'
      );
    }
  }

  /** Grade fields are system-managed; writes follow the class-level checks above. */
  private without sharing class Writer {
    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
