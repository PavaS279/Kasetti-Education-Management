/**
 * Class session scheduling: generation from weekly patterns, conflict
 * detection, rescheduling, cancellation, and ad-hoc sessions.
 *
 * Times are interpreted in the running user's time zone (the branch's local
 * time for staff working at that branch).
 */
public with sharing class SessionService {
  public static final String STATUS_SCHEDULED = 'Scheduled';
  public static final String STATUS_CANCELLED = 'Cancelled';

  public class Conflict {
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id sessionId;
    @AuraEnabled
    public Boolean blocking;
  }

  public class GenerationResult {
    @AuraEnabled
    public Integer created = 0;
    @AuraEnabled
    public Integer skippedExisting = 0;
    @AuraEnabled
    public Integer skippedClosures = 0;
    @AuraEnabled
    public List<String> conflicts = new List<String>();
  }

  // ------------------------------------------------------------ generation

  /** Generates sessions for every weekly pattern of the class. Idempotent. */
  public static GenerationResult generate(Id offeringId) {
    CourseOffering offering = EnrolmentService.loadOffering(offeringId, false);
    CourseOffering details = [
      SELECT
        Id,
        Room__c,
        Teacher_User__c,
        Branch__c,
        Delivery_Mode__c,
        StartDate,
        EndDate
      FROM CourseOffering
      WHERE Id = :offeringId
      WITH USER_MODE
    ];
    List<CourseOfferingSchedule> patterns = [
      SELECT
        Id,
        StartDate,
        EndDate,
        StartTime,
        EndTime,
        IsMonday,
        IsTuesday,
        IsWednesday,
        IsThursday,
        IsFriday,
        IsSaturday,
        IsSunday,
        Type
      FROM CourseOfferingSchedule
      WHERE CourseOfferingId = :offeringId
      WITH USER_MODE
    ];
    if (patterns.isEmpty()) {
      throw new AppException(
        'Add a weekly pattern to the class before generating sessions.'
      );
    }
    Integer horizon = AppSettings.getInteger('Session_Horizon_Days', 366);
    Date horizonEnd = Date.today().addDays(horizon);
    List<Calendar_Closure__c> closures = closuresFor(details.Branch__c);
    Set<String> existingKeys = new Set<String>();
    for (Class_Session__c existing : [
      SELECT External_Id__c
      FROM Class_Session__c
      WHERE Course_Offering__c = :offeringId
      WITH SYSTEM_MODE
    ]) {
      existingKeys.add(existing.External_Id__c);
    }

    GenerationResult result = new GenerationResult();
    List<Class_Session__c> sessions = new List<Class_Session__c>();
    for (CourseOfferingSchedule pattern : patterns) {
      if (pattern.StartTime == null || pattern.EndTime == null) {
        throw new AppException('Weekly pattern needs a start and end time.');
      }
      Date fromDate = firstNonNull(
        pattern.StartDate,
        details.StartDate == null ? null : details.StartDate.date(),
        Date.today()
      );
      Date toDate = firstNonNull(
        pattern.EndDate,
        details.EndDate == null ? null : details.EndDate.date(),
        horizonEnd
      );
      if (toDate > horizonEnd) {
        toDate = horizonEnd;
      }
      for (Date day = fromDate; day <= toDate; day = day.addDays(1)) {
        if (!runsOn(pattern, day)) {
          continue;
        }
        if (isClosed(day, closures)) {
          result.skippedClosures++;
          continue;
        }
        Datetime startAt = Datetime.newInstance(day, pattern.StartTime);
        String key = offeringId + ':' + startAt.getTime();
        if (existingKeys.contains(key)) {
          result.skippedExisting++;
          continue;
        }
        existingKeys.add(key);
        sessions.add(
          new Class_Session__c(
            Name = (offering.Name + ' · ' + day.format()).left(80),
            Course_Offering__c = offeringId,
            Branch__c = details.Branch__c,
            Room__c = details.Room__c,
            Teacher_User__c = details.Teacher_User__c,
            Delivery_Mode__c = details.Delivery_Mode__c,
            Start__c = startAt,
            End__c = Datetime.newInstance(day, pattern.EndTime),
            Status__c = STATUS_SCHEDULED,
            Session_Type__c = pattern.Type == 'Lab'
              ? 'Lab'
              : (pattern.Type == 'Exam' ? 'Exam' : 'Class'),
            Schedule__c = pattern.Id,
            External_Id__c = key
          )
        );
      }
    }
    if (sessions.isEmpty()) {
      return result;
    }
    // Teacher/room conflicts are rejected per session by the trigger; generation
    // keeps the rest and reports what could not be scheduled.
    List<Database.SaveResult> saves = Database.insert(
      sessions,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < saves.size(); i++) {
      if (saves[i].isSuccess()) {
        result.created++;
      } else {
        result.conflicts.add(
          sessions[i].Start__c.format() +
            ': ' +
            saves[i].getErrors()[0].getMessage()
        );
      }
    }
    return result;
  }

  // -------------------------------------------------------------- conflicts

  /** Teacher and room double-bookings (blocking) for the given sessions. */
  public static Map<Integer, List<Conflict>> findConflicts(
    List<Class_Session__c> sessions
  ) {
    Map<Integer, List<Conflict>> conflicts = new Map<Integer, List<Conflict>>();
    Set<Id> teachers = new Set<Id>();
    Set<Id> rooms = new Set<Id>();
    Datetime minStart;
    Datetime maxEnd;
    for (Class_Session__c s : sessions) {
      if (
        s.Status__c == STATUS_CANCELLED ||
        s.Start__c == null ||
        s.End__c == null
      ) {
        continue;
      }
      if (s.Teacher_User__c != null) {
        teachers.add(s.Teacher_User__c);
      }
      if (s.Room__c != null) {
        rooms.add(s.Room__c);
      }
      minStart = minStart == null ||
        s.Start__c < minStart
        ? s.Start__c
        : minStart;
      maxEnd = maxEnd == null || s.End__c > maxEnd ? s.End__c : maxEnd;
    }
    if (minStart == null || (teachers.isEmpty() && rooms.isEmpty())) {
      return conflicts;
    }
    List<Class_Session__c> others = [
      SELECT
        Id,
        Name,
        Status__c,
        Start__c,
        End__c,
        Teacher_User__c,
        Teacher_User__r.Name,
        Room__c,
        Room__r.Name
      FROM Class_Session__c
      WHERE
        Status__c != :STATUS_CANCELLED
        AND Start__c < :maxEnd
        AND End__c > :minStart
        AND (Teacher_User__c IN :teachers
        OR Room__c IN :rooms)
      WITH SYSTEM_MODE
    ];
    for (Integer i = 0; i < sessions.size(); i++) {
      Class_Session__c s = sessions[i];
      if (
        s.Status__c == STATUS_CANCELLED ||
        s.Start__c == null ||
        s.End__c == null
      ) {
        continue;
      }
      List<Class_Session__c> candidates = new List<Class_Session__c>(others);
      // Sessions earlier in the same batch also count.
      for (Integer j = 0; j < i; j++) {
        candidates.add(sessions[j]);
      }
      for (Class_Session__c other : candidates) {
        if (
          (s.Id != null &&
          other.Id == s.Id) ||
          other === s ||
          other.Status__c == STATUS_CANCELLED
        ) {
          continue;
        }
        if (!(other.Start__c < s.End__c && other.End__c > s.Start__c)) {
          continue;
        }
        if (
          s.Teacher_User__c != null &&
          other.Teacher_User__c == s.Teacher_User__c
        ) {
          add(
            conflicts,
            i,
            'Teacher',
            'The teacher is already teaching ' + label(other) + '.',
            other.Id
          );
        }
        if (s.Room__c != null && other.Room__c == s.Room__c) {
          add(
            conflicts,
            i,
            'Room',
            'The room is already booked for ' + label(other) + '.',
            other.Id
          );
        }
      }
    }
    return conflicts;
  }

  /** Learners of this class who are enrolled in another class at the new time (warnings). */
  public static List<Conflict> learnerConflicts(
    Id offeringId,
    Datetime startAt,
    Datetime endAt,
    Id excludeSessionId
  ) {
    Set<Id> learners = new Set<Id>();
    for (CourseOfferingParticipant p : [
      SELECT ParticipantContactId
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :offeringId
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH SYSTEM_MODE
    ]) {
      learners.add(p.ParticipantContactId);
    }
    List<Conflict> result = new List<Conflict>();
    if (learners.isEmpty()) {
      return result;
    }
    Map<Id, Set<Id>> learnersByOffering = new Map<Id, Set<Id>>();
    for (CourseOfferingParticipant p : [
      SELECT CourseOfferingId, ParticipantContactId
      FROM CourseOfferingParticipant
      WHERE
        ParticipantContactId IN :learners
        AND CourseOfferingId != :offeringId
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH SYSTEM_MODE
    ]) {
      if (!learnersByOffering.containsKey(p.CourseOfferingId)) {
        learnersByOffering.put(p.CourseOfferingId, new Set<Id>());
      }
      learnersByOffering.get(p.CourseOfferingId).add(p.ParticipantContactId);
    }
    if (learnersByOffering.isEmpty()) {
      return result;
    }
    for (Class_Session__c other : [
      SELECT Id, Name, Start__c, End__c, Course_Offering__c
      FROM Class_Session__c
      WHERE
        Course_Offering__c IN :learnersByOffering.keySet()
        AND Status__c != :STATUS_CANCELLED
        AND Start__c < :endAt
        AND End__c > :startAt
        AND Id != :excludeSessionId
      WITH SYSTEM_MODE
    ]) {
      Conflict c = new Conflict();
      c.kind = 'Learner';
      c.blocking = false;
      c.sessionId = other.Id;
      Integer count = learnersByOffering.get(other.Course_Offering__c).size();
      c.message =
        count +
        ' learner' +
        (count == 1 ? '' : 's') +
        ' also attend ' +
        label(other) +
        '.';
      result.add(c);
    }
    return result;
  }

  // ------------------------------------------------------------- changes

  public static void reschedule(
    Id sessionId,
    Datetime newStart,
    Datetime newEnd,
    Id newRoomId,
    String reason
  ) {
    if (newStart == null || newEnd == null || newEnd <= newStart) {
      throw new AppException('Choose a valid new start and end.');
    }
    Class_Session__c session = load(sessionId);
    if (session.Status__c == STATUS_CANCELLED) {
      throw new AppException(
        'Cancelled sessions cannot be moved. Restore or add a make-up session instead.'
      );
    }
    Class_Session__c changes = new Class_Session__c(
      Id = sessionId,
      Start__c = newStart,
      End__c = newEnd,
      Room__c = newRoomId == null ? session.Room__c : newRoomId,
      Cancellation_Reason__c = reason
    );
    write(
      changes,
      new Class_Session__c(
        Id = sessionId,
        Original_Start__c = session.Original_Start__c == null
          ? session.Start__c
          : session.Original_Start__c,
        Rescheduled__c = true
      )
    );
  }

  public static void cancel(Id sessionId, String reason) {
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for cancelling the session.');
    }
    Class_Session__c session = load(sessionId);
    if (session.Status__c != STATUS_SCHEDULED) {
      throw new AppException('Only scheduled sessions can be cancelled.');
    }
    write(
      new Class_Session__c(
        Id = sessionId,
        Status__c = STATUS_CANCELLED,
        Cancellation_Reason__c = reason
      ),
      null
    );
    MessageService.sessionCancelled(sessionId);
  }

  public static Id addSession(
    Id offeringId,
    Datetime startAt,
    Datetime endAt,
    String sessionType,
    Id roomId
  ) {
    if (startAt == null || endAt == null || endAt <= startAt) {
      throw new AppException('Choose a valid start and end.');
    }
    CourseOffering offering = EnrolmentService.loadOffering(offeringId, false);
    CourseOffering details = [
      SELECT Room__c, Teacher_User__c, Delivery_Mode__c
      FROM CourseOffering
      WHERE Id = :offeringId
      WITH USER_MODE
    ];
    Class_Session__c session = new Class_Session__c(
      Name = (offering.Name +
        ' · ' +
        startAt.date().format() +
        ' (' +
        sessionType +
        ')')
        .left(80),
      Course_Offering__c = offeringId,
      Branch__c = offering.Branch__c,
      Room__c = roomId == null ? details.Room__c : roomId,
      Teacher_User__c = details.Teacher_User__c,
      Delivery_Mode__c = details.Delivery_Mode__c,
      Start__c = startAt,
      End__c = endAt,
      Status__c = STATUS_SCHEDULED,
      Session_Type__c = String.isBlank(sessionType) ? 'Extra' : sessionType
    );
    Database.SaveResult result = Database.insert(
      session,
      false,
      AccessLevel.USER_MODE
    );
    if (!result.isSuccess()) {
      throw new AppException(result.getErrors()[0].getMessage());
    }
    return session.Id;
  }

  // -------------------------------------------------------------- helpers

  private static void write(
    Class_Session__c userChanges,
    Class_Session__c systemChanges
  ) {
    Database.SaveResult result = Database.update(
      userChanges,
      false,
      AccessLevel.USER_MODE
    );
    if (!result.isSuccess()) {
      throw new AppException(result.getErrors()[0].getMessage());
    }
    if (systemChanges != null) {
      Database.update(systemChanges, AccessLevel.SYSTEM_MODE);
    }
  }

  public static Class_Session__c load(Id sessionId) {
    List<Class_Session__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Start__c,
        End__c,
        Room__c,
        Teacher_User__c,
        Course_Offering__c,
        Original_Start__c,
        Attendance_Marked__c
      FROM Class_Session__c
      WHERE Id = :sessionId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Session not found or not accessible.');
    }
    return rows[0];
  }

  private static List<Calendar_Closure__c> closuresFor(Id branchId) {
    return [
      SELECT Start_Date__c, End_Date__c
      FROM Calendar_Closure__c
      WHERE Branch__c = NULL OR Branch__c = :branchId
      WITH SYSTEM_MODE
    ];
  }

  private static Boolean isClosed(
    Date day,
    List<Calendar_Closure__c> closures
  ) {
    for (Calendar_Closure__c closure : closures) {
      if (day >= closure.Start_Date__c && day <= closure.End_Date__c) {
        return true;
      }
    }
    return false;
  }

  @TestVisible
  private static Boolean runsOn(CourseOfferingSchedule pattern, Date day) {
    // 1900-01-07 was a Sunday; daysBetween mod 7 gives 0=Sunday … 6=Saturday.
    Integer weekday = Math.mod(
      Date.newInstance(1900, 1, 7).daysBetween(day),
      7
    );
    switch on weekday {
      when 0 {
        return pattern.IsSunday;
      }
      when 1 {
        return pattern.IsMonday;
      }
      when 2 {
        return pattern.IsTuesday;
      }
      when 3 {
        return pattern.IsWednesday;
      }
      when 4 {
        return pattern.IsThursday;
      }
      when 5 {
        return pattern.IsFriday;
      }
      when else {
        return pattern.IsSaturday;
      }
    }
  }

  private static Date firstNonNull(Date a, Date b, Date c) {
    return a != null ? a : (b != null ? b : c);
  }

  private static void add(
    Map<Integer, List<Conflict>> conflicts,
    Integer index,
    String kind,
    String message,
    Id otherId
  ) {
    if (!conflicts.containsKey(index)) {
      conflicts.put(index, new List<Conflict>());
    }
    Conflict c = new Conflict();
    c.kind = kind;
    c.message = message;
    c.sessionId = otherId;
    c.blocking = true;
    conflicts.get(index).add(c);
  }

  private static String label(Class_Session__c session) {
    return session.Name +
      (session.Start__c == null ? '' : ' (' + session.Start__c.format() + ')');
  }
}
