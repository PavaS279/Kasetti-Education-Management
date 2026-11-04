/**
 * Resource substitution (F2.6): teacher absences, cover teachers and room swaps.
 *
 * Recording an absence flags every scheduled session the teacher has in the
 * period as Needs Cover. Each flagged session is then either given a cover
 * teacher (ranked suggestions: free at that time, not absent, has taught the
 * course, lightest load that day) or cancelled (families are notified through
 * F2.5). Rooms can be swapped for any active room of the branch that is free
 * and large enough. Every change goes through the session trigger's teacher and
 * room double-booking checks.
 *
 * Teachers may report their own absence; arranging cover and changing rooms
 * needs edit access to sessions' teacher and room (schedulers).
 */
public with sharing class CoverService {
  public static final String TEACHER_ROLE = 'Teacher';
  private static final Set<String> OPEN_ABSENCE = new Set<String>{
    'Needs Cover',
    'Partially Covered',
    'Covered'
  };

  public class AbsenceRequest {
    @AuraEnabled
    public Id teacherId { get; set; }
    @AuraEnabled
    public Datetime startAt { get; set; }
    @AuraEnabled
    public Datetime endAt { get; set; }
    @AuraEnabled
    public String reason { get; set; }
    @AuraEnabled
    public String notes { get; set; }
  }

  public class Candidate {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Boolean free;
    @AuraEnabled
    public Boolean taughtCourse;
    @AuraEnabled
    public Integer sessionsThatDay;
    @AuraEnabled
    public String clash;
  }

  public class RoomOption {
    @AuraEnabled
    public Id roomId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String roomType;
    @AuraEnabled
    public Integer capacity;
    @AuraEnabled
    public Boolean free;
    @AuraEnabled
    public Boolean bigEnough;
    @AuraEnabled
    public String clash;
  }

  public class SessionCover {
    @AuraEnabled
    public Class_Session__c session;
    @AuraEnabled
    public Integer learners;
    @AuraEnabled
    public List<Candidate> candidates = new List<Candidate>();
  }

  public class CoverDesk {
    @AuraEnabled
    public List<Staff_Absence__c> absences;
    @AuraEnabled
    public List<SessionCover> uncovered = new List<SessionCover>();
    @AuraEnabled
    public List<User> teachers = new List<User>();
    @AuraEnabled
    public Boolean canArrange;
    @AuraEnabled
    public Id currentUserId;
  }

  // ------------------------------------------------------------- absences

  /** Records an absence and flags the teacher's sessions in the period for cover. */
  public static Id recordAbsence(AbsenceRequest request) {
    if (request == null || request.startAt == null || request.endAt == null) {
      throw new AppException('Enter when the absence starts and ends.');
    }
    if (request.endAt <= request.startAt) {
      throw new AppException('The absence must end after it starts.');
    }
    if (String.isBlank(request.reason)) {
      throw new AppException('Choose the reason for the absence.');
    }
    Id teacherId = request.teacherId == null
      ? UserInfo.getUserId()
      : request.teacherId;
    if (teacherId != UserInfo.getUserId() && !canArrange()) {
      throw new AppException(
        'You can report your own absence. Ask a scheduler to record absences for others.'
      );
    }
    if (!Schema.SObjectType.Staff_Absence__c.isCreateable()) {
      throw new AppException('You do not have permission to report absences.');
    }
    for (Staff_Absence__c existing : [
      SELECT Id, Name
      FROM Staff_Absence__c
      WHERE
        Staff_User__c = :teacherId
        AND Status__c IN :OPEN_ABSENCE
        AND Start__c < :request.endAt
        AND End__c > :request.startAt
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      throw new AppException(
        'This teacher already has an absence in that period (' +
          existing.Name +
          ').'
      );
    }
    List<Class_Session__c> sessions = teacherSessions(
      teacherId,
      request.startAt,
      request.endAt
    );
    Staff_Absence__c absence = new Staff_Absence__c(
      Staff_User__c = teacherId,
      Branch__c = sessions.isEmpty()
        ? branchOf(teacherId)
        : sessions[0].Branch__c,
      Start__c = request.startAt,
      End__c = request.endAt,
      Reason__c = request.reason,
      Notes__c = request.notes == null ? null : request.notes.left(255),
      Reported_By__c = UserInfo.getUserId(),
      Status__c = 'Needs Cover',
      Sessions_Affected__c = sessions.size(),
      Sessions_Handled__c = 0
    );
    Writer writer = new Writer();
    writer.insertRecords(new List<SObject>{ absence });
    List<Class_Session__c> flags = new List<Class_Session__c>();
    for (Class_Session__c session : sessions) {
      flags.add(
        new Class_Session__c(
          Id = session.Id,
          Needs_Cover__c = true,
          Staff_Absence__c = absence.Id
        )
      );
    }
    writer.updateRecords(flags);
    refreshAbsences(new Set<Id>{ absence.Id });
    return absence.Id;
  }

  /** Withdraws an absence: sessions still waiting for cover go back to the teacher. */
  public static void withdrawAbsence(Id absenceId) {
    Staff_Absence__c absence = loadAbsence(absenceId);
    if (absence.Staff_User__c != UserInfo.getUserId()) {
      assertCanArrange();
    }
    if (absence.Status__c == 'Withdrawn') {
      throw new AppException('This absence is already withdrawn.');
    }
    List<Class_Session__c> released = new List<Class_Session__c>();
    for (Class_Session__c session : [
      SELECT Id
      FROM Class_Session__c
      WHERE Staff_Absence__c = :absenceId AND Needs_Cover__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      released.add(
        new Class_Session__c(Id = session.Id, Needs_Cover__c = false)
      );
    }
    Writer writer = new Writer();
    writer.updateRecords(released);
    writer.updateRecords(
      new List<SObject>{
        new Staff_Absence__c(Id = absenceId, Status__c = 'Withdrawn')
      }
    );
  }

  // ----------------------------------------------------------------- cover

  /** Cover teachers for a session, best first. */
  public static List<Candidate> candidates(Id sessionId) {
    Class_Session__c session = loadSession(sessionId);
    return rank(new List<Class_Session__c>{ session }).get(session.Id);
  }

  /** Puts a cover teacher on the session; the scheduled teacher is kept as the original. */
  public static void assignCover(Id sessionId, Id coverUserId, String note) {
    assertCanArrange();
    if (coverUserId == null) {
      throw new AppException('Choose the cover teacher.');
    }
    Class_Session__c session = loadSession(sessionId);
    if (session.Status__c != SessionService.STATUS_SCHEDULED) {
      throw new AppException('Only scheduled sessions can be covered.');
    }
    Id original = session.Original_Teacher__c == null
      ? session.Teacher_User__c
      : session.Original_Teacher__c;
    if (coverUserId == session.Teacher_User__c) {
      throw new AppException('That teacher is already teaching this session.');
    }
    if (isAbsent(coverUserId, session.Start__c, session.End__c)) {
      throw new AppException('That teacher is absent at this time.');
    }
    // Teacher double-bookings are rejected by the session trigger.
    Database.SaveResult result = Database.update(
      new Class_Session__c(Id = sessionId, Teacher_User__c = coverUserId),
      false,
      AccessLevel.USER_MODE
    );
    if (!result.isSuccess()) {
      throw new AppException(result.getErrors()[0].getMessage());
    }
    Boolean returningToOriginal = coverUserId == original;
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Class_Session__c(
            Id = sessionId,
            Needs_Cover__c = false,
            Original_Teacher__c = returningToOriginal ? null : original,
            Teacher_Attendance__c = returningToOriginal ? null : 'Substituted',
            Cover_Note__c = String.isBlank(note) ? null : note.left(255)
          )
        }
      );
    if (!returningToOriginal) {
      new Writer()
        .insertRecords(
          new List<SObject>{
            new Task(
              OwnerId = coverUserId,
              WhatId = sessionId,
              Subject = 'Cover: ' + session.Course_Offering__r.Name,
              Description = 'You are covering ' +
                session.Course_Offering__r.Name +
                ' on ' +
                session.Start__c.format() +
                (String.isBlank(note) ? '.' : '. ' + note),
              ActivityDate = session.Start__c.date(),
              Priority = 'High',
              Status = 'Not Started'
            )
          }
        );
    }
    refreshAbsences(new Set<Id>{ session.Staff_Absence__c });
  }

  /** Cancels a session that cannot be covered; families are notified. */
  public static void cancelForAbsence(Id sessionId, String reason) {
    assertCanArrange();
    Class_Session__c session = loadSession(sessionId);
    SessionService.cancel(
      sessionId,
      String.isBlank(reason) ? 'Teacher unavailable' : reason
    );
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Class_Session__c(Id = sessionId, Needs_Cover__c = false)
        }
      );
    refreshAbsences(new Set<Id>{ session.Staff_Absence__c });
  }

  // ----------------------------------------------------------------- rooms

  /** Active rooms of the session's branch, free and large enough first. */
  public static List<RoomOption> roomOptions(Id sessionId) {
    Class_Session__c session = loadSession(sessionId);
    Integer learners = learnerCount(session.Course_Offering__c);
    List<Room__c> rooms = [
      SELECT Id, Name, Room_Type__c, Capacity__c
      FROM Room__c
      WHERE
        Branch__c = :session.Branch__c
        AND Active__c = TRUE
        AND Id != :session.Room__c
      WITH SYSTEM_MODE
      ORDER BY Capacity__c, Name
    ];
    Map<Id, String> clashes = new Map<Id, String>();
    for (Class_Session__c other : [
      SELECT Room__c, Course_Offering__r.Name, Start__c
      FROM Class_Session__c
      WHERE
        Room__c IN :new Map<Id, Room__c>(rooms).keySet()
        AND Status__c != :SessionService.STATUS_CANCELLED
        AND Start__c < :session.End__c
        AND End__c > :session.Start__c
      WITH SYSTEM_MODE
    ]) {
      clashes.put(
        other.Room__c,
        'Booked for ' + other.Course_Offering__r?.Name
      );
    }
    List<RoomOption> free = new List<RoomOption>();
    List<RoomOption> other = new List<RoomOption>();
    for (Room__c room : rooms) {
      RoomOption option = new RoomOption();
      option.roomId = room.Id;
      option.name = room.Name;
      option.roomType = room.Room_Type__c;
      option.capacity = room.Capacity__c == null
        ? 0
        : room.Capacity__c.intValue();
      option.free = !clashes.containsKey(room.Id);
      option.bigEnough = option.capacity >= learners;
      option.clash = clashes.get(room.Id);
      if (option.free && option.bigEnough) {
        free.add(option);
      } else {
        other.add(option);
      }
    }
    free.addAll(other);
    return free;
  }

  /** Moves the session to another room; the original room is kept for reference. */
  public static void swapRoom(Id sessionId, Id roomId, String note) {
    assertCanArrange();
    if (roomId == null) {
      throw new AppException('Choose the new room.');
    }
    Class_Session__c session = loadSession(sessionId);
    if (session.Status__c != SessionService.STATUS_SCHEDULED) {
      throw new AppException('Only scheduled sessions can change room.');
    }
    Room__c room = [
      SELECT Id, Capacity__c, Active__c, Branch__c
      FROM Room__c
      WHERE Id = :roomId
      WITH SYSTEM_MODE
    ];
    if (!room.Active__c || room.Branch__c != session.Branch__c) {
      throw new AppException('Choose an active room of the same branch.');
    }
    Integer learners = learnerCount(session.Course_Offering__c);
    if (room.Capacity__c != null && room.Capacity__c < learners) {
      throw new AppException(
        'The room holds ' +
          room.Capacity__c.intValue() +
          ' but ' +
          learners +
          ' learners are enrolled.'
      );
    }
    Database.SaveResult result = Database.update(
      new Class_Session__c(Id = sessionId, Room__c = roomId),
      false,
      AccessLevel.USER_MODE
    );
    if (!result.isSuccess()) {
      throw new AppException(result.getErrors()[0].getMessage());
    }
    Id original = session.Original_Room__c == null
      ? session.Room__c
      : session.Original_Room__c;
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Class_Session__c(
            Id = sessionId,
            Original_Room__c = original == roomId ? null : original,
            Cover_Note__c = String.isBlank(note)
              ? session.Cover_Note__c
              : note.left(255)
          )
        }
      );
  }

  // ----------------------------------------------------------------- reads

  /** Open absences from today on and the sessions still needing cover, with suggestions. */
  public static CoverDesk desk() {
    CoverDesk result = new CoverDesk();
    Datetime now = System.now();
    result.absences = [
      SELECT
        Id,
        Name,
        Staff_User__c,
        Staff_User__r.Name,
        Branch__r.Name,
        Start__c,
        End__c,
        Reason__c,
        Notes__c,
        Status__c,
        Sessions_Affected__c,
        Sessions_Handled__c
      FROM Staff_Absence__c
      WHERE End__c >= :now AND Status__c != 'Withdrawn'
      WITH USER_MODE
      ORDER BY Start__c
      LIMIT 50
    ];
    List<Class_Session__c> sessions = [
      SELECT
        Id,
        Name,
        Start__c,
        End__c,
        Status__c,
        Branch__c,
        Room__c,
        Room__r.Name,
        Teacher_User__c,
        Teacher_User__r.Name,
        Original_Teacher__c,
        Original_Room__c,
        Cover_Note__c,
        Staff_Absence__c,
        Course_Offering__c,
        Course_Offering__r.Name,
        Course_Offering__r.LearningCourseId
      FROM Class_Session__c
      WHERE Needs_Cover__c = TRUE AND Start__c >= :now
      WITH USER_MODE
      ORDER BY Start__c
      LIMIT 30
    ];
    Map<Id, List<Candidate>> ranked = rank(sessions);
    Map<Id, Integer> learners = learnerCounts(sessions);
    for (Class_Session__c session : sessions) {
      SessionCover cover = new SessionCover();
      cover.session = session;
      cover.learners = learners.get(session.Course_Offering__c);
      cover.candidates = ranked.get(session.Id);
      result.uncovered.add(cover);
    }
    result.canArrange = canArrange();
    result.currentUserId = UserInfo.getUserId();
    if (result.canArrange) {
      result.teachers = teachers();
    }
    return result;
  }

  // --------------------------------------------------------------- ranking

  private static Map<Id, List<Candidate>> rank(
    List<Class_Session__c> sessions
  ) {
    Map<Id, List<Candidate>> result = new Map<Id, List<Candidate>>();
    if (sessions.isEmpty()) {
      return result;
    }
    Set<Id> branches = new Set<Id>();
    Datetime minStart;
    Datetime maxEnd;
    for (Class_Session__c s : sessions) {
      branches.add(s.Branch__c);
      minStart = minStart == null ||
        s.Start__c < minStart
        ? s.Start__c
        : minStart;
      maxEnd = maxEnd == null || s.End__c > maxEnd ? s.End__c : maxEnd;
    }
    Map<Id, Set<Id>> teachersByBranch = new Map<Id, Set<Id>>();
    Map<Id, String> names = new Map<Id, String>();
    for (Branch_Staff__c staff : [
      SELECT Branch__c, User__c, User__r.Name
      FROM Branch_Staff__c
      WHERE
        Branch__c IN :branches
        AND Role__c = :TEACHER_ROLE
        AND Active__c = TRUE
        AND User__r.IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (!teachersByBranch.containsKey(staff.Branch__c)) {
        teachersByBranch.put(staff.Branch__c, new Set<Id>());
      }
      teachersByBranch.get(staff.Branch__c).add(staff.User__c);
      names.put(staff.User__c, staff.User__r.Name);
    }
    if (names.isEmpty()) {
      for (Class_Session__c s : sessions) {
        result.put(s.Id, new List<Candidate>());
      }
      return result;
    }
    Date firstDay = minStart.date();
    Date lastDay = maxEnd.date().addDays(1);
    Datetime dayStart = Datetime.newInstance(
      firstDay,
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime dayEnd = Datetime.newInstance(
      lastDay,
      Time.newInstance(0, 0, 0, 0)
    );
    List<Class_Session__c> busy = [
      SELECT Id, Teacher_User__c, Start__c, End__c, Course_Offering__r.Name
      FROM Class_Session__c
      WHERE
        Teacher_User__c IN :names.keySet()
        AND Status__c != :SessionService.STATUS_CANCELLED
        AND Start__c < :dayEnd
        AND End__c > :dayStart
      WITH SYSTEM_MODE
    ];
    List<Staff_Absence__c> absences = [
      SELECT Staff_User__c, Start__c, End__c
      FROM Staff_Absence__c
      WHERE
        Staff_User__c IN :names.keySet()
        AND Status__c IN :OPEN_ABSENCE
        AND Start__c < :maxEnd
        AND End__c > :minStart
      WITH SYSTEM_MODE
    ];
    Set<Id> courses = new Set<Id>();
    for (Class_Session__c s : sessions) {
      courses.add(s.Course_Offering__r?.LearningCourseId);
    }
    Set<String> experience = new Set<String>();
    for (CourseOffering offering : [
      SELECT Teacher_User__c, LearningCourseId
      FROM CourseOffering
      WHERE Teacher_User__c IN :names.keySet() AND LearningCourseId IN :courses
      WITH SYSTEM_MODE
    ]) {
      experience.add(
        offering.Teacher_User__c + '|' + offering.LearningCourseId
      );
    }
    for (Class_Session__c s : sessions) {
      List<Candidate> options = new List<Candidate>();
      Set<Id> pool = teachersByBranch.get(s.Branch__c);
      if (pool == null) {
        result.put(s.Id, options);
        continue;
      }
      Id absent = s.Original_Teacher__c == null
        ? s.Teacher_User__c
        : s.Original_Teacher__c;
      for (Id userId : pool) {
        if (userId == absent || userId == s.Teacher_User__c) {
          continue;
        }
        Candidate c = new Candidate();
        c.userId = userId;
        c.name = names.get(userId);
        c.free = true;
        c.sessionsThatDay = 0;
        c.taughtCourse = experience.contains(
          userId + '|' + s.Course_Offering__r?.LearningCourseId
        );
        for (Class_Session__c other : busy) {
          if (other.Teacher_User__c != userId || other.Id == s.Id) {
            continue;
          }
          if (other.Start__c.date() == s.Start__c.date()) {
            c.sessionsThatDay++;
          }
          if (other.Start__c < s.End__c && other.End__c > s.Start__c) {
            c.free = false;
            c.clash = 'Teaching ' + other.Course_Offering__r?.Name;
          }
        }
        for (Staff_Absence__c away : absences) {
          if (
            away.Staff_User__c == userId &&
            away.Start__c < s.End__c &&
            away.End__c > s.Start__c
          ) {
            c.free = false;
            c.clash = 'Absent';
          }
        }
        options.add(c);
      }
      result.put(s.Id, sortCandidates(options));
    }
    return result;
  }

  @TestVisible
  private static List<Candidate> sortCandidates(List<Candidate> options) {
    List<Candidate> sorted = new List<Candidate>();
    for (Candidate c : options) {
      Integer i = 0;
      while (i < sorted.size() && !better(c, sorted[i])) {
        i++;
      }
      if (i == sorted.size()) {
        sorted.add(c);
      } else {
        sorted.add(i, c);
      }
    }
    return sorted;
  }

  private static Boolean better(Candidate a, Candidate b) {
    if (a.free != b.free) {
      return a.free;
    }
    if (a.taughtCourse != b.taughtCourse) {
      return a.taughtCourse;
    }
    if (a.sessionsThatDay != b.sessionsThatDay) {
      return a.sessionsThatDay < b.sessionsThatDay;
    }
    return a.name < b.name;
  }

  // --------------------------------------------------------------- helpers

  private static void refreshAbsences(Set<Id> absenceIds) {
    absenceIds.remove(null);
    if (absenceIds.isEmpty()) {
      return;
    }
    Map<Id, Integer> affected = new Map<Id, Integer>();
    Map<Id, Integer> waiting = new Map<Id, Integer>();
    for (Id absenceId : absenceIds) {
      affected.put(absenceId, 0);
      waiting.put(absenceId, 0);
    }
    for (Class_Session__c session : [
      SELECT Staff_Absence__c, Needs_Cover__c
      FROM Class_Session__c
      WHERE Staff_Absence__c IN :absenceIds
      WITH SYSTEM_MODE
    ]) {
      affected.put(
        session.Staff_Absence__c,
        affected.get(session.Staff_Absence__c) + 1
      );
      if (session.Needs_Cover__c) {
        waiting.put(
          session.Staff_Absence__c,
          waiting.get(session.Staff_Absence__c) + 1
        );
      }
    }
    List<Staff_Absence__c> updates = new List<Staff_Absence__c>();
    for (Staff_Absence__c absence : [
      SELECT Id, Status__c
      FROM Staff_Absence__c
      WHERE Id IN :absenceIds
      WITH SYSTEM_MODE
    ]) {
      if (absence.Status__c == 'Withdrawn') {
        continue;
      }
      Integer total = affected.get(absence.Id);
      Integer open = waiting.get(absence.Id);
      updates.add(
        new Staff_Absence__c(
          Id = absence.Id,
          Sessions_Affected__c = total,
          Sessions_Handled__c = total - open,
          Status__c = open == 0
            ? 'Covered'
            : open == total ? 'Needs Cover' : 'Partially Covered'
        )
      );
    }
    new Writer().updateRecords(updates);
  }

  private static List<Class_Session__c> teacherSessions(
    Id teacherId,
    Datetime startAt,
    Datetime endAt
  ) {
    return [
      SELECT Id, Branch__c
      FROM Class_Session__c
      WHERE
        Teacher_User__c = :teacherId
        AND Status__c = :SessionService.STATUS_SCHEDULED
        AND Start__c < :endAt
        AND End__c > :startAt
      WITH SYSTEM_MODE
      ORDER BY Start__c
    ];
  }

  private static Boolean isAbsent(Id userId, Datetime startAt, Datetime endAt) {
    return [
        SELECT COUNT()
        FROM Staff_Absence__c
        WHERE
          Staff_User__c = :userId
          AND Status__c IN :OPEN_ABSENCE
          AND Start__c < :endAt
          AND End__c > :startAt
        WITH SYSTEM_MODE
      ] > 0;
  }

  private static Id branchOf(Id userId) {
    for (Branch_Staff__c staff : [
      SELECT Branch__c
      FROM Branch_Staff__c
      WHERE User__c = :userId AND Active__c = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      return staff.Branch__c;
    }
    return null;
  }

  /** Active teachers on branch staff lists the user can see. */
  private static List<User> teachers() {
    Set<Id> userIds = new Set<Id>();
    for (Branch_Staff__c staff : [
      SELECT User__c
      FROM Branch_Staff__c
      WHERE
        Role__c = :TEACHER_ROLE
        AND Active__c = TRUE
        AND User__r.IsActive = TRUE
      WITH USER_MODE
      LIMIT 500
    ]) {
      userIds.add(staff.User__c);
    }
    return [
      SELECT Id, Name
      FROM User
      WHERE Id IN :userIds
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
  }

  private static Integer learnerCount(Id offeringId) {
    return [
      SELECT COUNT()
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :offeringId
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH SYSTEM_MODE
    ];
  }

  private static Map<Id, Integer> learnerCounts(
    List<Class_Session__c> sessions
  ) {
    Map<Id, Integer> counts = new Map<Id, Integer>();
    Set<Id> offerings = new Set<Id>();
    for (Class_Session__c s : sessions) {
      offerings.add(s.Course_Offering__c);
      counts.put(s.Course_Offering__c, 0);
    }
    for (AggregateResult row : [
      SELECT CourseOfferingId offering, COUNT(Id) total
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId IN :offerings
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH SYSTEM_MODE
      GROUP BY CourseOfferingId
    ]) {
      counts.put((Id) row.get('offering'), (Integer) row.get('total'));
    }
    return counts;
  }

  public static Boolean canArrange() {
    return Schema.SObjectType.Class_Session__c.fields.Teacher_User__c.isUpdateable() &&
      Schema.SObjectType.Class_Session__c.fields.Room__c.isUpdateable();
  }

  private static void assertCanArrange() {
    if (!canArrange()) {
      throw new AppException(
        'You do not have permission to arrange cover or change rooms.'
      );
    }
  }

  private static Class_Session__c loadSession(Id sessionId) {
    List<Class_Session__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Start__c,
        End__c,
        Branch__c,
        Room__c,
        Teacher_User__c,
        Original_Teacher__c,
        Original_Room__c,
        Cover_Note__c,
        Staff_Absence__c,
        Course_Offering__c,
        Course_Offering__r.Name,
        Course_Offering__r.LearningCourseId
      FROM Class_Session__c
      WHERE Id = :sessionId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Session not found or not accessible.');
    }
    return rows[0];
  }

  private static Staff_Absence__c loadAbsence(Id absenceId) {
    List<Staff_Absence__c> rows = [
      SELECT Id, Status__c, Staff_User__c
      FROM Staff_Absence__c
      WHERE Id = :absenceId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Absence not found or not accessible.');
    }
    return rows[0];
  }

  /** System-managed cover fields, authorised by the permission checks above. */
  private without sharing class Writer {
    void insertRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
      }
    }

    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
