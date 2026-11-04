/** Lightning controller for the weekly timetable and class scheduling actions. */
public with sharing class TimetableController {
  public class SessionView {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id classId;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String courseName;
    @AuraEnabled
    public Datetime startAt;
    @AuraEnabled
    public Datetime endAt;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String sessionType;
    @AuraEnabled
    public Id roomId;
    @AuraEnabled
    public String roomName;
    @AuraEnabled
    public String teacherName;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public Boolean rescheduled;
    @AuraEnabled
    public Boolean attendanceMarked;
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

  public class Filters {
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> teachers = new List<Option>();
    @AuraEnabled
    public List<Option> rooms = new List<Option>();
    @AuraEnabled
    public Id currentUserId = UserInfo.getUserId();
  }

  public class MovePreview {
    @AuraEnabled
    public List<SessionService.Conflict> conflicts = new List<SessionService.Conflict>();
    @AuraEnabled
    public Boolean blocked = false;
  }

  @AuraEnabled(cacheable=true)
  public static List<SessionView> getWeek(
    Date weekStart,
    Id branchId,
    Id teacherId,
    Id roomId
  ) {
    try {
      Date startDay = weekStart == null
        ? Date.today().toStartOfWeek()
        : weekStart;
      Datetime fromAt = Datetime.newInstance(
        startDay,
        Time.newInstance(0, 0, 0, 0)
      );
      Datetime toAt = fromAt.addDays(7);
      String query =
        'SELECT Id, Name, Course_Offering__c, Course_Offering__r.Name, Course_Offering__r.LearningCourse.Name, Start__c, End__c, ' +
        'Status__c, Session_Type__c, Room__c, Room__r.Name, Teacher_User__r.Name, Branch__r.Name, Rescheduled__c, Attendance_Marked__c ' +
        'FROM Class_Session__c WHERE Start__c >= :fromAt AND Start__c < :toAt';
      if (branchId != null) {
        query += ' AND Branch__c = :branchId';
      }
      if (teacherId != null) {
        query += ' AND Teacher_User__c = :teacherId';
      }
      if (roomId != null) {
        query += ' AND Room__c = :roomId';
      }
      query += ' ORDER BY Start__c LIMIT 1000';
      List<SessionView> views = new List<SessionView>();
      for (
        SObject row : Database.queryWithBinds(
          query,
          new Map<String, Object>{
            'fromAt' => fromAt,
            'toAt' => toAt,
            'branchId' => branchId,
            'teacherId' => teacherId,
            'roomId' => roomId
          },
          AccessLevel.USER_MODE
        )
      ) {
        views.add(toView((Class_Session__c) row));
      }
      return views;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static Filters getFilters() {
    try {
      Filters filters = new Filters();
      for (Branch__c branch : [
        SELECT Id, Name
        FROM Branch__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        filters.branches.add(new Option(branch.Name, branch.Id));
      }
      Map<Id, String> teachers = new Map<Id, String>();
      for (Branch_Staff__c staff : [
        SELECT User__c, User__r.Name
        FROM Branch_Staff__c
        WHERE Role__c = 'Teacher' AND Active__c = TRUE
        WITH USER_MODE
        LIMIT 500
      ]) {
        teachers.put(staff.User__c, staff.User__r.Name);
      }
      for (CourseOffering offering : [
        SELECT Teacher_User__c, Teacher_User__r.Name
        FROM CourseOffering
        WHERE Teacher_User__c != NULL
        WITH USER_MODE
        LIMIT 500
      ]) {
        teachers.put(offering.Teacher_User__c, offering.Teacher_User__r.Name);
      }
      for (Id userId : teachers.keySet()) {
        filters.teachers.add(new Option(teachers.get(userId), userId));
      }
      for (Room__c room : [
        SELECT Id, Name, Branch__r.Name
        FROM Room__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        ORDER BY Name
        LIMIT 500
      ]) {
        filters.rooms.add(
          new Option(room.Name + ' · ' + room.Branch__r.Name, room.Id)
        );
      }
      return filters;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Conflicts a move would cause, without saving. */
  @AuraEnabled
  public static MovePreview previewMove(
    Id sessionId,
    Datetime newStart,
    Datetime newEnd,
    Id newRoomId
  ) {
    try {
      Class_Session__c session = SessionService.load(sessionId);
      Class_Session__c candidate = session.clone(true, true);
      candidate.Start__c = newStart;
      candidate.End__c = newEnd;
      candidate.Room__c = newRoomId == null ? session.Room__c : newRoomId;
      MovePreview preview = new MovePreview();
      List<SessionService.Conflict> hard = SessionService.findConflicts(
          new List<Class_Session__c>{ candidate }
        )
        .get(0);
      if (hard != null) {
        preview.conflicts.addAll(hard);
        preview.blocked = true;
      }
      preview.conflicts.addAll(
        SessionService.learnerConflicts(
          session.Course_Offering__c,
          newStart,
          newEnd,
          sessionId
        )
      );
      return preview;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void reschedule(
    Id sessionId,
    Datetime newStart,
    Datetime newEnd,
    Id newRoomId,
    String reason
  ) {
    try {
      SessionService.reschedule(sessionId, newStart, newEnd, newRoomId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void cancelSession(Id sessionId, String reason) {
    try {
      SessionService.cancel(sessionId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id addSession(
    Id offeringId,
    Datetime startAt,
    Datetime endAt,
    String sessionType,
    Id roomId
  ) {
    try {
      return SessionService.addSession(
        offeringId,
        startAt,
        endAt,
        sessionType,
        roomId
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static SessionService.GenerationResult generateSessions(
    Id offeringId
  ) {
    try {
      return SessionService.generate(offeringId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  private static SessionView toView(Class_Session__c s) {
    SessionView v = new SessionView();
    v.id = s.Id;
    v.name = s.Name;
    v.classId = s.Course_Offering__c;
    v.className = s.Course_Offering__r?.Name;
    v.courseName = s.Course_Offering__r?.LearningCourse?.Name;
    v.startAt = s.Start__c;
    v.endAt = s.End__c;
    v.status = s.Status__c;
    v.sessionType = s.Session_Type__c;
    v.roomId = s.Room__c;
    v.roomName = s.Room__r?.Name;
    v.teacherName = s.Teacher_User__r?.Name;
    v.branchName = s.Branch__r?.Name;
    v.rescheduled = s.Rescheduled__c;
    v.attendanceMarked = s.Attendance_Marked__c;
    return v;
  }
}
