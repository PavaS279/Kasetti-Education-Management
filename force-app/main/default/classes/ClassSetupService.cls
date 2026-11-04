/**
 * Class set-up after creation: the teacher (login), faculty, room, branch,
 * seats, delivery and status of an existing class, from the class page or
 * straight from a Set-up Centre gap.
 *
 * Sessions copy the class's teacher and room when they are generated, so a
 * change of teacher or room is carried to the class's upcoming scheduled
 * sessions (propagate(), also run by the class trigger for edits made in
 * the standard form). A session that would clash keeps its old teacher or
 * room and is reported; sessions being covered keep their cover teacher.
 */
public with sharing class ClassSetupService {
  /** The last propagation in this transaction, for the screen to report. */
  @TestVisible
  private static Propagation lastPropagation;

  public class Propagation {
    @AuraEnabled
    public Integer updated = 0;
    @AuraEnabled
    public List<String> clashes = new List<String>();
  }

  // ----------------------------------------------------------------- details

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String detail;
    Option(String label, String value, String detail) {
      this.label = label;
      this.value = value;
      this.detail = detail;
    }
  }

  public class Details {
    @AuraEnabled
    public Id classId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String course;
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public Id roomId;
    @AuraEnabled
    public Id teacherUserId;
    @AuraEnabled
    public Id facultyId;
    @AuraEnabled
    public Integer capacity;
    @AuraEnabled
    public Integer seatsTaken;
    @AuraEnabled
    public String deliveryMode;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer upcomingSessions = 0;
    @AuraEnabled
    public Integer upcomingWithoutTeacher = 0;
    @AuraEnabled
    public Integer patterns = 0;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> rooms = new List<Option>();
    @AuraEnabled
    public List<Option> teachers = new List<Option>();
    @AuraEnabled
    public List<Option> otherStaff = new List<Option>();
    @AuraEnabled
    public List<Option> faculty = new List<Option>();
    @AuraEnabled
    public List<Option> statuses = new List<Option>();
    @AuraEnabled
    public Boolean canCreateFaculty;
  }

  public static Details details(Id classId, Id branchId) {
    CourseOffering o = [
      SELECT
        Id,
        Name,
        LearningCourse.Name,
        Branch__c,
        Room__c,
        Teacher_User__c,
        PrimaryFacultyId,
        EnrollmentCapacity,
        Seats_Taken__c,
        Delivery_Mode__c,
        Class_Status__c
      FROM CourseOffering
      WHERE Id = :classId
      WITH USER_MODE
    ];
    Details d = new Details();
    d.classId = o.Id;
    d.name = o.Name;
    d.course = o.LearningCourse?.Name;
    d.branchId = branchId != null ? branchId : o.Branch__c;
    d.roomId = o.Room__c;
    d.teacherUserId = o.Teacher_User__c;
    d.facultyId = o.PrimaryFacultyId;
    d.capacity = o.EnrollmentCapacity;
    d.seatsTaken = o.Seats_Taken__c == null ? 0 : o.Seats_Taken__c.intValue();
    d.deliveryMode = o.Delivery_Mode__c;
    d.status = o.Class_Status__c;
    d.canEdit = Schema.SObjectType.CourseOffering.isUpdateable();
    d.canCreateFaculty = Schema.SObjectType.Contact.isCreateable();
    Datetime now = System.now();
    for (Class_Session__c s : [
      SELECT Teacher_User__c
      FROM Class_Session__c
      WHERE
        Course_Offering__c = :classId
        AND Start__c >= :now
        AND Status__c = :SessionService.STATUS_SCHEDULED
      WITH SYSTEM_MODE
    ]) {
      d.upcomingSessions++;
      if (s.Teacher_User__c == null) {
        d.upcomingWithoutTeacher++;
      }
    }
    d.patterns = [
      SELECT COUNT()
      FROM CourseOfferingSchedule
      WHERE CourseOfferingId = :classId
      WITH SYSTEM_MODE
    ];
    for (Branch__c b : [
      SELECT Id, Name
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      d.branches.add(new Option(b.Name, b.Id, null));
    }
    if (d.branchId != null) {
      CatalogSetupService.BranchChoices bc = CatalogSetupService.branchChoices(
        d.branchId
      );
      for (CatalogSetupService.Option r : bc.rooms) {
        d.rooms.add(new Option(r.label, r.value, r.detail));
      }
      Set<String> teacherIds = new Set<String>();
      for (CatalogSetupService.Option t : bc.teachers) {
        d.teachers.add(new Option(t.label, t.value, 'Teacher at this branch'));
        teacherIds.add(t.value);
      }
      // Other staff at the branch (coordinators, managers) can teach too.
      Set<Id> seen = new Set<Id>();
      for (Branch_Staff__c s : [
        SELECT User__c, User__r.Name, Role__c
        FROM Branch_Staff__c
        WHERE
          Branch__c = :d.branchId
          AND Active__c = TRUE
          AND Role__c != 'Teacher'
          AND User__r.IsActive = TRUE
        WITH SYSTEM_MODE
        ORDER BY User__r.Name
      ]) {
        if (!teacherIds.contains(s.User__c) && seen.add(s.User__c)) {
          d.otherStaff.add(new Option(s.User__r.Name, s.User__c, s.Role__c));
        }
      }
    }
    // The current teacher stays selectable even without a branch role.
    if (
      d.teacherUserId != null &&
      !hasValue(d.teachers, d.teacherUserId) &&
      !hasValue(d.otherStaff, d.teacherUserId)
    ) {
      for (User u : [
        SELECT Name
        FROM User
        WHERE Id = :d.teacherUserId
        WITH SYSTEM_MODE
      ]) {
        d.otherStaff.add(
          new Option(u.Name, d.teacherUserId, 'No role at this branch')
        );
      }
    }
    for (Contact f : CatalogSetupService.faculty()) {
      d.faculty.add(new Option(f.Name, f.Id, f.Title));
    }
    for (
      Schema.PicklistEntry e : CourseOffering.Class_Status__c.getDescribe()
        .getPicklistValues()
    ) {
      if (e.isActive()) {
        d.statuses.add(new Option(e.getLabel(), e.getValue(), null));
      }
    }
    return d;
  }

  private static Boolean hasValue(List<Option> options, Id value) {
    for (Option o : options) {
      if (o.value == value) {
        return true;
      }
    }
    return false;
  }

  // -------------------------------------------------------------------- save

  public class SaveRequest {
    @AuraEnabled
    public Id classId { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public Id roomId { get; set; }
    @AuraEnabled
    public Id teacherUserId { get; set; }
    @AuraEnabled
    public Id facultyId { get; set; }
    @AuraEnabled
    public Integer capacity { get; set; }
    @AuraEnabled
    public String deliveryMode { get; set; }
    @AuraEnabled
    public String status { get; set; }
  }

  /** Saves the class; teacher and room changes reach its upcoming sessions. */
  public static Propagation save(SaveRequest r) {
    if (!Schema.SObjectType.CourseOffering.isUpdateable()) {
      throw new AppException('You do not have access to change classes.');
    }
    if (r == null || r.classId == null) {
      throw new AppException('Choose the class.');
    }
    if (r.branchId == null) {
      throw new AppException('Choose the branch.');
    }
    if (r.capacity == null || r.capacity < 1) {
      throw new AppException('Enter the number of seats.');
    }
    CourseOffering current = [
      SELECT Seats_Taken__c
      FROM CourseOffering
      WHERE Id = :r.classId
      WITH USER_MODE
    ];
    Integer taken = current.Seats_Taken__c == null
      ? 0
      : current.Seats_Taken__c.intValue();
    if (r.capacity < taken) {
      throw new AppException(
        taken +
          ' learners are enrolled: the class needs at least ' +
          taken +
          ' seats.'
      );
    }
    if (r.roomId != null) {
      Room__c room = [
        SELECT Name, Branch__c, Capacity__c
        FROM Room__c
        WHERE Id = :r.roomId
        WITH USER_MODE
      ];
      if (room.Branch__c != r.branchId) {
        throw new AppException(room.Name + ' belongs to another branch.');
      }
      if (room.Capacity__c != null && r.capacity > room.Capacity__c) {
        throw new AppException(
          room.Name +
            ' seats ' +
            room.Capacity__c.intValue() +
            '; reduce the class size or choose a bigger room.'
        );
      }
    }
    lastPropagation = null;
    Database.update(
      new CourseOffering(
        Id = r.classId,
        Branch__c = r.branchId,
        Room__c = r.roomId,
        Teacher_User__c = r.teacherUserId,
        PrimaryFacultyId = r.facultyId,
        EnrollmentCapacity = r.capacity,
        Delivery_Mode__c = String.isBlank(r.deliveryMode)
          ? 'Classroom'
          : r.deliveryMode,
        Class_Status__c = r.status
      ),
      AccessLevel.USER_MODE
    );
    return lastPropagation == null ? new Propagation() : lastPropagation;
  }

  // ------------------------------------------------------------- propagation

  /**
   * Carries teacher and room changes to the classes' upcoming scheduled
   * sessions. Only sessions that still had the class's previous teacher
   * (or none) or previous room (or none) change; sessions under cover keep
   * their cover teacher; a session that would clash keeps its old value.
   */
  public static void propagate(
    List<CourseOffering> classes,
    Map<Id, SObject> oldMap
  ) {
    Map<Id, CourseOffering> changed = new Map<Id, CourseOffering>();
    for (CourseOffering o : classes) {
      CourseOffering before = (CourseOffering) oldMap.get(o.Id);
      if (
        o.Teacher_User__c != before.Teacher_User__c ||
        o.Room__c != before.Room__c
      ) {
        changed.put(o.Id, o);
      }
    }
    if (changed.isEmpty()) {
      return;
    }
    Propagation result = new Propagation();
    Datetime now = System.now();
    List<Class_Session__c> updates = new List<Class_Session__c>();
    for (Class_Session__c s : [
      SELECT
        Id,
        Name,
        Start__c,
        Course_Offering__c,
        Teacher_User__c,
        Room__c,
        Needs_Cover__c,
        Original_Teacher__c
      FROM Class_Session__c
      WHERE
        Course_Offering__c IN :changed.keySet()
        AND Start__c >= :now
        AND Status__c = :SessionService.STATUS_SCHEDULED
      WITH SYSTEM_MODE
      ORDER BY Start__c
      LIMIT 2000
    ]) {
      CourseOffering o = changed.get(s.Course_Offering__c);
      CourseOffering before = (CourseOffering) oldMap.get(o.Id);
      Class_Session__c u = new Class_Session__c(Id = s.Id);
      Boolean touched = false;
      Boolean covered =
        s.Needs_Cover__c == true ||
        s.Original_Teacher__c != null;
      if (
        o.Teacher_User__c != before.Teacher_User__c &&
        !covered &&
        (s.Teacher_User__c == null ||
        s.Teacher_User__c == before.Teacher_User__c)
      ) {
        u.Teacher_User__c = o.Teacher_User__c;
        touched = true;
      }
      if (
        o.Room__c != before.Room__c &&
        (s.Room__c == null ||
        s.Room__c == before.Room__c)
      ) {
        u.Room__c = o.Room__c;
        touched = true;
      }
      if (touched) {
        updates.add(u);
      }
    }
    List<Database.SaveResult> saves = Database.update(
      updates,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Map<Id, Class_Session__c> names = new Map<Id, Class_Session__c>(
      [
        SELECT Id, Start__c
        FROM Class_Session__c
        WHERE Id IN :new Map<Id, Class_Session__c>(updates).keySet()
        WITH SYSTEM_MODE
      ]
    );
    for (Integer i = 0; i < saves.size(); i++) {
      if (saves[i].isSuccess()) {
        result.updated++;
      } else {
        result.clashes.add(
          names.get(updates[i].Id).Start__c.format() +
            ': ' +
            saves[i].getErrors()[0].getMessage()
        );
      }
    }
    if (!result.clashes.isEmpty()) {
      Logger.warn(
        'ClassSetupService',
        result.clashes.size() +
          ' upcoming sessions kept their teacher or room because of clashes: ' +
          String.join(result.clashes, '; ').left(1000),
        null
      );
    }
    lastPropagation = result;
  }
}
