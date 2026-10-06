/**
 * Generic LMS integration: classes and rosters out, grades in.
 *
 * Reads run as the integration user (user mode), so the KEM Integration
 * persona decides what an LMS can see. Grades go through AssessmentService,
 * so the same validation and publication rules apply as in the gradebook.
 * Assessments created by the LMS carry its identifier in External_Id__c,
 * which makes re-sending the same grades safe.
 */
public with sharing class LmsService {
  public class GradeRequest {
    public Id classId;
    public AssessmentInput assessment;
    public List<ResultInput> results;
    public Boolean publish;
  }

  public class AssessmentInput {
    public String externalId;
    public String name;
    public String type;
    public Decimal maxScore;
    public Decimal weight;
    public Date assessmentDate;
  }

  public class ResultInput {
    public Id learnerId;
    public String learnerEmail;
    public Decimal score;
    public Boolean absent;
    public String feedback;
  }

  public class GradeResult {
    public Id assessmentId;
    public String status;
    public Integer results;
    public Boolean created;
  }

  // ------------------------------------------------------------- classes

  public static List<Map<String, Object>> classes(
    String branchCode,
    String status,
    Datetime modifiedSince
  ) {
    IntegrationService.assertIntegration();
    String query =
      'SELECT Id, Name, LearningCourseId, LearningCourse.Name, LearningCourse.External_ID__c, ' +
      'Branch__c, Branch__r.Branch_Code__c, Class_Status__c, StartDate, EndDate, EnrollmentCapacity, ' +
      'Seats_Taken__c, Delivery_Mode__c, Teacher_User__r.Email, Teacher_User__r.Name, LastModifiedDate ' +
      'FROM CourseOffering WHERE Branch__c != null';
    Map<String, Object> binds = new Map<String, Object>();
    if (String.isNotBlank(branchCode)) {
      query += ' AND Branch__r.Branch_Code__c = :branchCode';
      binds.put('branchCode', branchCode.trim().toUpperCase());
    }
    if (String.isNotBlank(status)) {
      query += ' AND Class_Status__c = :status';
      binds.put('status', status.trim());
    }
    if (modifiedSince != null) {
      query += ' AND LastModifiedDate >= :modifiedSince';
      binds.put('modifiedSince', modifiedSince);
    }
    query += ' ORDER BY LastModifiedDate LIMIT 2000';
    List<Map<String, Object>> rows = new List<Map<String, Object>>();
    for (
      CourseOffering offering : (List<CourseOffering>) Database.queryWithBinds(
        query,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      rows.add(classPayload(offering));
    }
    return rows;
  }

  public static Map<String, Object> classDetail(Id classId) {
    IntegrationService.assertIntegration();
    List<CourseOffering> rows = [
      SELECT
        Id,
        Name,
        LearningCourseId,
        LearningCourse.Name,
        LearningCourse.External_ID__c,
        Branch__c,
        Branch__r.Branch_Code__c,
        Class_Status__c,
        StartDate,
        EndDate,
        EnrollmentCapacity,
        Seats_Taken__c,
        Delivery_Mode__c,
        Teacher_User__r.Email,
        Teacher_User__r.Name,
        LastModifiedDate
      FROM CourseOffering
      WHERE Id = :classId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new NotFoundException('Class not found: ' + classId);
    }
    return classPayload(rows[0]);
  }

  public static Map<String, Object> roster(Id classId) {
    classDetail(classId);
    List<Object> learners = new List<Object>();
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        ParticipationStatus,
        ParticipantContactId,
        ParticipantContact.FirstName,
        ParticipantContact.LastName,
        ParticipantContact.Email
      FROM CourseOfferingParticipant
      WHERE CourseOfferingId = :classId
      WITH USER_MODE
      ORDER BY ParticipantContact.LastName
      LIMIT 2000
    ]) {
      learners.add(rosterEntry(enrolment));
    }
    return new Map<String, Object>{
      'classId' => classId,
      'learners' => learners
    };
  }

  public static Map<String, Object> classPayload(CourseOffering offering) {
    return new Map<String, Object>{
      'id' => offering.Id,
      'name' => offering.Name,
      'courseId' => offering.LearningCourseId,
      'courseName' => offering.LearningCourse?.Name,
      'courseCode' => offering.LearningCourse?.External_ID__c,
      'branchCode' => offering.Branch__r?.Branch_Code__c,
      'status' => offering.Class_Status__c,
      'startDate' => offering.StartDate,
      'endDate' => offering.EndDate,
      'capacity' => offering.EnrollmentCapacity,
      'deliveryMode' => offering.Delivery_Mode__c,
      'teacherEmail' => offering.Teacher_User__r?.Email,
      'teacherName' => offering.Teacher_User__r?.Name
    };
  }

  public static Map<String, Object> rosterEntry(
    CourseOfferingParticipant enrolment
  ) {
    return new Map<String, Object>{
      'enrolmentId' => enrolment.Id,
      'learnerId' => enrolment.ParticipantContactId,
      'firstName' => enrolment.ParticipantContact?.FirstName,
      'lastName' => enrolment.ParticipantContact?.LastName,
      'email' => enrolment.ParticipantContact?.Email,
      'status' => enrolment.ParticipationStatus
    };
  }

  // -------------------------------------------------------------- grades

  /** Creates or updates an assessment from the LMS with its results; optionally publishes it. All or nothing. */
  public static GradeResult saveGrades(GradeRequest request) {
    IntegrationService.assertIntegration();
    validate(request);
    classDetail(request.classId);
    AssessmentInput input = request.assessment;
    String externalId = input.externalId.trim();

    Map<Id, CourseOfferingParticipant> byContact = new Map<Id, CourseOfferingParticipant>();
    Map<String, CourseOfferingParticipant> byEmail = new Map<String, CourseOfferingParticipant>();
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        ParticipantContactId,
        ParticipantContact.Name,
        ParticipantContact.Email
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :request.classId
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH USER_MODE
    ]) {
      byContact.put(enrolment.ParticipantContactId, enrolment);
      if (String.isNotBlank(enrolment.ParticipantContact.Email)) {
        byEmail.put(
          enrolment.ParticipantContact.Email.toLowerCase(),
          enrolment
        );
      }
    }
    List<AssessmentService.ResultRow> rows = new List<AssessmentService.ResultRow>();
    List<String> unknown = new List<String>();
    for (ResultInput result : request.results) {
      CourseOfferingParticipant enrolment = result.learnerId != null
        ? byContact.get(result.learnerId)
        : (String.isBlank(result.learnerEmail)
            ? null
            : byEmail.get(result.learnerEmail.trim().toLowerCase()));
      if (enrolment == null) {
        unknown.add(
          result.learnerId != null
            ? String.valueOf(result.learnerId)
            : String.valueOf(result.learnerEmail)
        );
        continue;
      }
      AssessmentService.ResultRow row = new AssessmentService.ResultRow();
      row.learnerContactId = enrolment.ParticipantContactId;
      row.enrolmentId = enrolment.Id;
      row.learnerName = enrolment.ParticipantContact.Name;
      row.score = result.score;
      row.absent = result.absent == true;
      row.feedback = result.feedback;
      rows.add(row);
    }
    if (!unknown.isEmpty()) {
      throw new AppException(
        'Not enrolled in this class: ' + String.join(unknown, ', ') + '.'
      );
    }

    GradeResult outcome = new GradeResult();
    Savepoint sp = Database.setSavepoint();
    try {
      List<Course_Assessment__c> existing = [
        SELECT Id, Status__c, Course_Offering__c
        FROM Course_Assessment__c
        WHERE External_Id__c = :externalId
        WITH USER_MODE
      ];
      Course_Assessment__c assessment = new Course_Assessment__c(
        Name = input.name.trim().left(80),
        Assessment_Type__c = String.isBlank(input.type) ? 'Test' : input.type,
        Max_Score__c = input.maxScore,
        Weight__c = input.weight,
        Assessment_Date__c = input.assessmentDate
      );
      if (existing.isEmpty()) {
        assessment.Course_Offering__c = request.classId;
        assessment.External_Id__c = externalId;
        insert as user assessment;
        outcome.created = true;
      } else {
        if (existing[0].Course_Offering__c != request.classId) {
          throw new AppException(
            'Assessment ' + externalId + ' belongs to another class.'
          );
        }
        if (existing[0].Status__c == 'Published') {
          throw new AppException(
            'Assessment ' +
              externalId +
              ' is published; its results are locked.'
          );
        }
        assessment.Id = existing[0].Id;
        update as user assessment;
        outcome.created = false;
      }
      AssessmentService.saveResults(assessment.Id, rows);
      if (request.publish == true) {
        AssessmentService.publish(assessment.Id);
      }
      outcome.assessmentId = assessment.Id;
      outcome.results = rows.size();
      outcome.status = request.publish == true ? 'Published' : 'Draft';
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    return outcome;
  }

  private static void validate(GradeRequest request) {
    if (request == null || request.classId == null) {
      throw new AppException('classId is required.');
    }
    AssessmentInput input = request.assessment;
    if (input == null || String.isBlank(input.externalId)) {
      throw new AppException('assessment.externalId is required.');
    }
    if (String.isBlank(input.name)) {
      throw new AppException('assessment.name is required.');
    }
    if (input.maxScore == null || input.maxScore <= 0) {
      throw new AppException('assessment.maxScore must be greater than zero.');
    }
    if (request.results == null || request.results.isEmpty()) {
      throw new AppException('results must list at least one learner.');
    }
    if (request.results.size() > 500) {
      throw new AppException('Send at most 500 results at a time.');
    }
  }

  /** The requested record does not exist or is not visible (HTTP 404). */
  public class NotFoundException extends Exception {
  }
}
