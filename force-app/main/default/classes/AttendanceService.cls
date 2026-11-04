/**
 * Session attendance registers, corrections, and attendance statistics.
 *
 * Authorisation: the session's teacher, or anyone who can edit the session
 * (academic coordinators, branch managers, administrators). Attendance rows are
 * written in system mode after that check, because teachers only read sessions.
 */
public with sharing class AttendanceService {
  public static final Set<String> ATTENDED = new Set<String>{
    'Present',
    'Late'
  };
  public static final Set<String> COUNTED = new Set<String>{
    'Present',
    'Late',
    'Absent'
  };

  public class RegisterRow {
    @AuraEnabled
    public Id learnerContactId { get; set; }
    @AuraEnabled
    public Id learnerAccountId { get; set; }
    @AuraEnabled
    public Id enrolmentId { get; set; }
    @AuraEnabled
    public String learnerName { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public Decimal minutesLate { get; set; }
    @AuraEnabled
    public String note { get; set; }
    @AuraEnabled
    public Decimal attendanceRate { get; set; }
    @AuraEnabled
    public Boolean belowThreshold { get; set; }
  }

  public class Register {
    @AuraEnabled
    public Class_Session__c session;
    @AuraEnabled
    public List<RegisterRow> rows = new List<RegisterRow>();
    @AuraEnabled
    public Boolean canMark;
    @AuraEnabled
    public Boolean alreadyMarked;
  }

  public static Register getRegister(Id sessionId) {
    Register register = new Register();
    register.session = loadSession(sessionId);
    register.canMark = canMark(register.session);
    register.alreadyMarked = register.session.Attendance_Marked__c;
    Date sessionDate = register.session.Start__c.date();
    Map<Id, Session_Attendance__c> existing = new Map<Id, Session_Attendance__c>();
    for (Session_Attendance__c mark : [
      SELECT Learner__c, Status__c, Minutes_Late__c, Note__c
      FROM Session_Attendance__c
      WHERE Class_Session__c = :sessionId
      WITH SYSTEM_MODE
    ]) {
      existing.put(mark.Learner__c, mark);
    }
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        ParticipantContactId,
        ParticipantAccountId,
        ParticipantContact.Name,
        Attendance_Rate__c,
        Below_Attendance_Threshold__c,
        StartDate,
        EndDate
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :register.session.Course_Offering__c
        AND ParticipantAffiliation = 'Student'
        AND (ParticipationStatus IN :SeatService.SEAT_STATUSES
        OR ParticipationStatus = 'Completed'
        OR ParticipantContactId IN :existing.keySet())
      WITH SYSTEM_MODE
      ORDER BY ParticipantContact.Name
    ]) {
      Boolean activeOnDate =
        (enrolment.StartDate == null || enrolment.StartDate <= sessionDate) &&
        (enrolment.EndDate == null ||
        enrolment.EndDate >= sessionDate);
      Session_Attendance__c mark = existing.get(enrolment.ParticipantContactId);
      if (!activeOnDate && mark == null) {
        continue;
      }
      RegisterRow row = new RegisterRow();
      row.learnerContactId = enrolment.ParticipantContactId;
      row.learnerAccountId = enrolment.ParticipantAccountId;
      row.enrolmentId = enrolment.Id;
      row.learnerName = enrolment.ParticipantContact.Name;
      row.status = mark == null ? null : mark.Status__c;
      row.minutesLate = mark == null ? null : mark.Minutes_Late__c;
      row.note = mark == null ? null : mark.Note__c;
      row.attendanceRate = enrolment.Attendance_Rate__c;
      row.belowThreshold = enrolment.Below_Attendance_Threshold__c;
      register.rows.add(row);
    }
    return register;
  }

  public static void saveRegister(
    Id sessionId,
    List<RegisterRow> rows,
    String teacherAttendance
  ) {
    Class_Session__c session = loadSession(sessionId);
    if (!canMark(session)) {
      throw new AppException(
        'Only the session teacher or an academic coordinator can mark attendance.'
      );
    }
    if (session.Status__c == 'Cancelled') {
      throw new AppException(
        'Attendance cannot be taken for a cancelled session.'
      );
    }
    if (session.Start__c > System.now().addHours(1)) {
      throw new AppException(
        'Attendance can be taken from one hour before the session starts.'
      );
    }
    Map<Id, Session_Attendance__c> existing = new Map<Id, Session_Attendance__c>();
    for (Session_Attendance__c mark : [
      SELECT Id, Learner__c, Status__c
      FROM Session_Attendance__c
      WHERE Class_Session__c = :sessionId
      WITH SYSTEM_MODE
    ]) {
      existing.put(mark.Learner__c, mark);
    }
    List<Session_Attendance__c> upserts = new List<Session_Attendance__c>();
    Set<Id> enrolmentIds = new Set<Id>();
    for (RegisterRow row : rows) {
      if (String.isBlank(row.status)) {
        continue;
      }
      if (
        !new Set<String>{ 'Present', 'Late', 'Absent', 'Excused' }
          .contains(row.status)
      ) {
        throw new AppException('Unknown attendance status: ' + row.status);
      }
      Session_Attendance__c previous = existing.get(row.learnerContactId);
      Session_Attendance__c mark = new Session_Attendance__c(
        Unique_Key__c = sessionId + ':' + row.learnerContactId,
        Learner__c = row.learnerContactId,
        Enrolment__c = row.enrolmentId,
        Status__c = row.status,
        Minutes_Late__c = row.status == 'Late' ? row.minutesLate : null,
        Note__c = row.note == null ? null : row.note.left(255),
        Marked_By__c = UserInfo.getUserId(),
        Marked_At__c = System.now()
      );
      if (previous == null) {
        mark.Class_Session__c = sessionId;
      } else if (previous.Status__c != row.status) {
        mark.Corrected__c = true;
        mark.Previous_Status__c = previous.Status__c;
      }
      upserts.add(mark);
      enrolmentIds.add(row.enrolmentId);
    }
    if (upserts.isEmpty()) {
      throw new AppException('Mark at least one learner.');
    }
    Savepoint sp = Database.setSavepoint();
    try {
      new Writer().upsertMarks(upserts);
      Class_Session__c changes = new Class_Session__c(
        Id = sessionId,
        Attendance_Marked__c = true,
        Teacher_Attendance__c = teacherAttendance
      );
      if (
        session.Status__c == 'Scheduled' &&
        session.Start__c <= System.now()
      ) {
        changes.Status__c = 'Completed';
      }
      new Writer().updateRecords(new List<SObject>{ changes });
      recalculate(enrolmentIds);
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  /** Recomputes attendance statistics and threshold flags for enrolments. */
  public static void recalculate(Set<Id> enrolmentIds) {
    enrolmentIds.remove(null);
    if (enrolmentIds.isEmpty()) {
      return;
    }
    Map<Id, Integer> attendedCount = new Map<Id, Integer>();
    Map<Id, Integer> countedCount = new Map<Id, Integer>();
    for (AggregateResult row : [
      SELECT Enrolment__c enrolment, Status__c status, COUNT(Id) total
      FROM Session_Attendance__c
      WHERE
        Enrolment__c IN :enrolmentIds
        AND Class_Session__r.Status__c != 'Cancelled'
      WITH SYSTEM_MODE
      GROUP BY Enrolment__c, Status__c
    ]) {
      Id enrolmentId = (Id) row.get('enrolment');
      String status = (String) row.get('status');
      Integer total = (Integer) row.get('total');
      if (COUNTED.contains(status)) {
        countedCount.put(
          enrolmentId,
          (countedCount.containsKey(enrolmentId)
            ? countedCount.get(enrolmentId)
            : 0) + total
        );
      }
      if (ATTENDED.contains(status)) {
        attendedCount.put(
          enrolmentId,
          (attendedCount.containsKey(enrolmentId)
            ? attendedCount.get(enrolmentId)
            : 0) + total
        );
      }
    }
    List<CourseOfferingParticipant> updates = new List<CourseOfferingParticipant>();
    List<Task> alerts = new List<Task>();
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        ParticipantContactId,
        ParticipantContact.Name,
        Below_Attendance_Threshold__c,
        CourseOffering.Name,
        CourseOffering.Branch__c,
        CourseOffering.Branch__r.Attendance_Threshold__c,
        CourseOffering.Branch__r.Tax_Rate__c,
        CourseOffering.Branch__r.Invoice_Due_Days__c,
        CourseOffering.Branch__r.Invoice_Prefix__c,
        CourseOffering.Branch__r.Branch_Manager__c,
        CourseOffering.Teacher_User__c
      FROM CourseOfferingParticipant
      WHERE Id IN :enrolmentIds
      WITH SYSTEM_MODE
    ]) {
      Integer total = countedCount.containsKey(enrolment.Id)
        ? countedCount.get(enrolment.Id)
        : 0;
      Integer present = attendedCount.containsKey(enrolment.Id)
        ? attendedCount.get(enrolment.Id)
        : 0;
      Decimal rate = total == 0 ? null : (Decimal.valueOf(present) / total);
      Decimal threshold = new BranchPolicy(enrolment.CourseOffering.Branch__r)
        .attendanceThreshold();
      Boolean below = rate != null && rate < threshold;
      updates.add(
        new CourseOfferingParticipant(
          Id = enrolment.Id,
          Sessions_Attended__c = present,
          Sessions_Missed__c = total - present,
          Attendance_Rate__c = rate == null ? null : (rate * 100).setScale(2),
          Below_Attendance_Threshold__c = below
        )
      );
      Id owner = enrolment.CourseOffering.Branch__r?.Branch_Manager__c != null
        ? enrolment.CourseOffering.Branch__r.Branch_Manager__c
        : enrolment.CourseOffering.Teacher_User__c;
      if (below && !enrolment.Below_Attendance_Threshold__c && owner != null) {
        alerts.add(
          new Task(
            OwnerId = owner,
            WhoId = enrolment.ParticipantContactId,
            WhatId = enrolment.Id,
            Subject = 'Attendance below threshold: ' +
              enrolment.ParticipantContact.Name,
            Description = enrolment.ParticipantContact.Name +
              ' is at ' +
              (rate * 100).setScale(0) +
              '% in ' +
              enrolment.CourseOffering.Name +
              ' (threshold ' +
              (threshold * 100).setScale(0) +
              '%). Contact the learner and guardian.',
            Priority = 'High',
            Status = 'Not Started',
            ActivityDate = Date.today().addDays(2)
          )
        );
      }
    }
    new Writer().updateRecords(updates);
    if (!alerts.isEmpty()) {
      Logger.errors(
        'AttendanceService.alerts',
        new Writer().insertPartial(alerts)
      );
    }
  }

  @TestVisible
  private static Boolean canMark(Class_Session__c session) {
    if (session.Teacher_User__c == UserInfo.getUserId()) {
      return true;
    }
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :session.Id
    ];
    return !access.isEmpty() &&
      access[0].HasEditAccess &&
      Schema.SObjectType.Class_Session__c.isUpdateable();
  }

  private static Class_Session__c loadSession(Id sessionId) {
    List<Class_Session__c> rows = [
      SELECT
        Id,
        Name,
        Start__c,
        End__c,
        Status__c,
        Teacher_User__c,
        Teacher_User__r.Name,
        Course_Offering__c,
        Course_Offering__r.Name,
        Room__r.Name,
        Attendance_Marked__c,
        Teacher_Attendance__c
      FROM Class_Session__c
      WHERE Id = :sessionId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Session not found or not accessible.');
    }
    return rows[0];
  }

  /**
   * Writes authorised by the attendance rules above (session teacher or session
   * editor), not by record ownership: teachers only have read access to
   * sessions and enrolments, so attendance rows, session completion, and
   * enrolment statistics are written without sharing.
   */
  private without sharing class Writer {
    void upsertMarks(List<Session_Attendance__c> marks) {
      Database.upsert(
        marks,
        Session_Attendance__c.Unique_Key__c,
        AccessLevel.SYSTEM_MODE
      );
    }

    void updateRecords(List<SObject> records) {
      Database.update(records, AccessLevel.SYSTEM_MODE);
    }

    List<Database.SaveResult> insertPartial(List<SObject> records) {
      return Database.insert(records, false, AccessLevel.SYSTEM_MODE);
    }
  }
}
