/**
 * Guided creation of courses, classes and faculty (Phase 5 stage 3).
 *
 * - Course: the Education Cloud Learning record, the course and its prices in
 *   one step (all or nothing).
 * - Class: details, room and capacity, teacher and faculty, weekly patterns
 *   and term dates; preview() runs the real session generation inside a
 *   savepoint and rolls it back, so the preview shows exactly the sessions,
 *   holidays skipped and teacher/room clashes that create() would produce.
 * - Faculty: teaching staff shown on classes (contacts of the faculty account;
 *   they need no Salesforce licence).
 */
public with sharing class CatalogSetupService {
  private static final List<String> DAYS = new List<String>{
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  };

  // ------------------------------------------------------------------ course

  public class PriceLine {
    @AuraEnabled
    public String feeType { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String description { get; set; }
  }

  public class CourseRequest {
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String code { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public Integer minAge { get; set; }
    @AuraEnabled
    public Integer maxAge { get; set; }
    @AuraEnabled
    public Date pricesFrom { get; set; }
    @AuraEnabled
    public List<PriceLine> prices { get; set; }
  }

  public static Id createCourse(CourseRequest request) {
    if (!Schema.SObjectType.LearningCourse.isCreateable()) {
      throw new AppException('You do not have access to create courses.');
    }
    String name = request?.name == null ? '' : request.name.trim();
    if (String.isBlank(name)) {
      throw new AppException('Enter the course name.');
    }
    String code = String.isBlank(request.code)
      ? null
      : request.code.trim().toUpperCase();
    if (
      code != null &&
      [
        SELECT COUNT()
        FROM LearningCourse
        WHERE External_ID__c = :code
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException('Course code ' + code + ' is already used.');
    }
    if (
      [SELECT COUNT() FROM LearningCourse WHERE Name = :name WITH SYSTEM_MODE] >
      0
    ) {
      throw new AppException('A course called ' + name + ' already exists.');
    }
    if (
      request.minAge != null &&
      request.maxAge != null &&
      request.minAge > request.maxAge
    ) {
      throw new AppException(
        'The minimum age cannot be above the maximum age.'
      );
    }
    List<PriceLine> prices = request.prices == null
      ? new List<PriceLine>()
      : request.prices;
    for (PriceLine p : prices) {
      if (String.isBlank(p.feeType) || String.isBlank(p.frequency)) {
        throw new AppException(
          'Choose the fee type and how often it is charged for every price.'
        );
      }
      if (p.amount == null || p.amount <= 0) {
        throw new AppException('Every price needs an amount above zero.');
      }
    }
    if (!prices.isEmpty() && !Schema.SObjectType.Fee_Price__c.isCreateable()) {
      throw new AppException('You do not have access to create prices.');
    }
    Savepoint sp = Database.setSavepoint();
    try {
      Learning learning = new Learning(
        Name = name.left(80),
        Type = 'LearningCourse',
        IsActive = true
      );
      Database.insert(learning, AccessLevel.USER_MODE);
      LearningCourse course = new LearningCourse(
        Name = name.left(80),
        LearningId = learning.Id,
        External_ID__c = code,
        Description = request.description,
        Minimum_Age__c = request.minAge,
        Maximum_Age__c = request.maxAge
      );
      Database.insert(course, AccessLevel.USER_MODE);
      Date fromDate = request.pricesFrom == null
        ? Date.today()
        : request.pricesFrom;
      List<Fee_Price__c> rows = new List<Fee_Price__c>();
      for (PriceLine p : prices) {
        rows.add(
          new Fee_Price__c(
            Learning_Course__c = course.Id,
            Fee_Type__c = p.feeType,
            Billing_Frequency__c = p.frequency,
            Amount__c = p.amount,
            Branch__c = p.branchId,
            Description__c = String.isBlank(p.description)
              ? defaultDescription(p)
              : p.description,
            Effective_From__c = fromDate,
            Active__c = true
          )
        );
      }
      Database.insert(rows, AccessLevel.USER_MODE);
      return course.Id;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  private static String defaultDescription(PriceLine p) {
    if (p.feeType == 'Tuition') {
      return p.frequency == 'Monthly'
        ? 'Monthly tuition'
        : (p.frequency == 'Term' ? 'Term tuition' : 'Tuition');
    }
    return p.feeType == 'Materials' ? 'Kit and materials' : p.feeType;
  }

  // ------------------------------------------------------------------- class

  public class PatternLine {
    @AuraEnabled
    public List<String> days { get; set; }
    @AuraEnabled
    public String startTime { get; set; } // HH:mm
    @AuraEnabled
    public Integer minutes { get; set; }
  }

  public class ClassRequest {
    @AuraEnabled
    public Id courseId { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String section { get; set; }
    @AuraEnabled
    public String deliveryMode { get; set; }
    @AuraEnabled
    public Id roomId { get; set; }
    @AuraEnabled
    public Integer capacity { get; set; }
    @AuraEnabled
    public Id teacherUserId { get; set; }
    @AuraEnabled
    public Id facultyId { get; set; }
    @AuraEnabled
    public Date startDate { get; set; }
    @AuraEnabled
    public Date endDate { get; set; }
    @AuraEnabled
    public Boolean openForEnrolment { get; set; }
    @AuraEnabled
    public List<PatternLine> patterns { get; set; }
  }

  public class ClassPreview {
    @AuraEnabled
    public Integer sessions = 0;
    @AuraEnabled
    public Integer skippedHolidays = 0;
    @AuraEnabled
    public List<String> clashes = new List<String>();
    @AuraEnabled
    public List<Datetime> firstSessions = new List<Datetime>();
    @AuraEnabled
    public Datetime lastSession;
    @AuraEnabled
    public List<String> warnings = new List<String>();
    @AuraEnabled
    public Id classId;
  }

  /** What create() would produce; nothing is saved. */
  public static ClassPreview previewClass(ClassRequest request) {
    Savepoint sp = Database.setSavepoint();
    try {
      ClassPreview result = build(request);
      result.classId = null;
      return result;
    } finally {
      Database.rollback(sp);
    }
  }

  /** Creates the class; refused when no session could be created (all clash or none fall in the dates). */
  public static ClassPreview createClass(ClassRequest request) {
    Savepoint sp = Database.setSavepoint();
    try {
      ClassPreview result = build(request);
      if (result.sessions == 0) {
        throw new AppException(
          'No sessions can be created: none fall between the first and last day on the chosen days, or every one clashes. Change the dates, days, time, room or teacher.'
        );
      }
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  private static ClassPreview build(ClassRequest r) {
    if (!Schema.SObjectType.CourseOffering.isCreateable()) {
      throw new AppException('You do not have access to create classes.');
    }
    ClassPreview result = new ClassPreview();
    if (r == null || r.courseId == null) {
      throw new AppException('Choose the course.');
    }
    if (r.branchId == null) {
      throw new AppException('Choose the branch.');
    }
    if (r.startDate == null || r.endDate == null || r.endDate < r.startDate) {
      throw new AppException(
        'Enter the term dates; the last day cannot be before the first.'
      );
    }
    if (r.capacity == null || r.capacity < 1) {
      throw new AppException('Enter the number of seats.');
    }
    if (r.patterns == null || r.patterns.isEmpty()) {
      throw new AppException('Add at least one weekly time.');
    }
    String mode = String.isBlank(r.deliveryMode) ? 'Classroom' : r.deliveryMode;
    LearningCourse course = [
      SELECT Id, Name
      FROM LearningCourse
      WHERE Id = :r.courseId
      WITH USER_MODE
    ];
    if (r.roomId != null) {
      Room__c room = [
        SELECT Id, Name, Capacity__c, Branch__c
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
    } else if (mode != 'Online') {
      result.warnings.add(
        'No room chosen: the timetable cannot check room clashes.'
      );
    }
    if (r.teacherUserId == null && r.facultyId == null) {
      result.warnings.add('No teacher chosen: registers and cover need one.');
    }
    if (
      r.teacherUserId != null &&
      [
        SELECT COUNT()
        FROM Branch_Staff__c
        WHERE
          Branch__c = :r.branchId
          AND User__c = :r.teacherUserId
          AND Role__c = 'Teacher'
          AND Active__c = TRUE
        WITH SYSTEM_MODE
      ] == 0
    ) {
      result.warnings.add(
        'The chosen teacher is not a teacher at this branch.'
      );
    }
    if (
      [
        SELECT COUNT()
        FROM Fee_Price__c
        WHERE
          Learning_Course__c = :r.courseId
          AND Active__c = TRUE
          AND Fee_Type__c = 'Tuition'
        WITH SYSTEM_MODE
      ] == 0
    ) {
      result.warnings.add(
        course.Name + ' has no tuition price: enrolments would be free.'
      );
    }
    String name = String.isBlank(r.name)
      ? defaultName(course.Name, r.patterns)
      : r.name.trim();

    CourseOffering o = new CourseOffering(
      Name = name.left(80),
      LearningCourseId = r.courseId,
      Branch__c = r.branchId,
      SectionNumber = String.isBlank(r.section) ? null : r.section.trim(),
      Delivery_Mode__c = mode,
      Room__c = r.roomId,
      EnrollmentCapacity = r.capacity,
      Teacher_User__c = r.teacherUserId,
      PrimaryFacultyId = r.facultyId,
      Class_Status__c = r.openForEnrolment == true ? 'Open' : 'Planned',
      StartDate = Datetime.newInstance(
        r.startDate,
        Time.newInstance(0, 0, 0, 0)
      ),
      EndDate = Datetime.newInstance(r.endDate, Time.newInstance(23, 59, 0, 0))
    );
    Database.insert(o, AccessLevel.USER_MODE);
    List<CourseOfferingSchedule> patterns = new List<CourseOfferingSchedule>();
    for (PatternLine p : r.patterns) {
      patterns.add(pattern(o.Id, p, r.startDate));
    }
    Database.insert(patterns, AccessLevel.USER_MODE);
    SessionService.GenerationResult g = SessionService.generate(o.Id);
    result.sessions = g.created;
    result.skippedHolidays = g.skippedClosures;
    result.clashes = g.conflicts;
    for (Class_Session__c s : [
      SELECT Start__c
      FROM Class_Session__c
      WHERE Course_Offering__c = :o.Id
      WITH SYSTEM_MODE
      ORDER BY Start__c
    ]) {
      if (result.firstSessions.size() < 4) {
        result.firstSessions.add(s.Start__c);
      }
      result.lastSession = s.Start__c;
    }
    result.classId = o.Id;
    return result;
  }

  private static CourseOfferingSchedule pattern(
    Id classId,
    PatternLine p,
    Date startDate
  ) {
    if (p.days == null || p.days.isEmpty()) {
      throw new AppException('Choose the day(s) for every weekly time.');
    }
    if (
      String.isBlank(p.startTime) ||
      !Pattern.matches('\\d{1,2}:\\d{2}', p.startTime)
    ) {
      throw new AppException('Enter a start time such as 16:30.');
    }
    Integer minutes = p.minutes == null ? 60 : p.minutes;
    if (minutes < 15 || minutes > 480) {
      throw new AppException('A class lasts between 15 minutes and 8 hours.');
    }
    Time st = Time.newInstance(
      Integer.valueOf(p.startTime.substringBefore(':')),
      Integer.valueOf(p.startTime.substringAfter(':')),
      0,
      0
    );
    Set<String> days = new Set<String>(p.days);
    List<String> labels = new List<String>();
    for (String d : DAYS) {
      if (days.contains(d)) {
        labels.add(d);
      }
    }
    return new CourseOfferingSchedule(
      CourseOfferingId = classId,
      Description = String.join(labels, ', ') + ' ' + p.startTime,
      StartTime = st,
      EndTime = st.addMinutes(minutes),
      StartDate = startDate,
      IsMonday = days.contains('Mon'),
      IsTuesday = days.contains('Tue'),
      IsWednesday = days.contains('Wed'),
      IsThursday = days.contains('Thu'),
      IsFriday = days.contains('Fri'),
      IsSaturday = days.contains('Sat'),
      IsSunday = days.contains('Sun')
    );
  }

  /** "Python for Kids – Saturday 12:00" */
  @TestVisible
  private static String defaultName(
    String courseName,
    List<PatternLine> patterns
  ) {
    Map<String, String> full = new Map<String, String>{
      'Mon' => 'Monday',
      'Tue' => 'Tuesday',
      'Wed' => 'Wednesday',
      'Thu' => 'Thursday',
      'Fri' => 'Friday',
      'Sat' => 'Saturday',
      'Sun' => 'Sunday'
    };
    PatternLine first = patterns[0];
    List<String> names = new List<String>();
    for (String d : DAYS) {
      if (first.days != null && first.days.contains(d)) {
        names.add(full.get(d));
      }
    }
    return courseName +
      ' – ' +
      String.join(names, ' and ') +
      ' ' +
      first.startTime;
  }

  // ------------------------------------------------------------- choices

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

  public class Choices {
    @AuraEnabled
    public List<Option> courses = new List<Option>();
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> faculty = new List<Option>();
    @AuraEnabled
    public Boolean canCreateFaculty;
    @AuraEnabled
    public Boolean canPrice;
  }

  public static Choices choices() {
    Choices c = new Choices();
    for (LearningCourse course : [
      SELECT Id, Name
      FROM LearningCourse
      WHERE IsActive = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      c.courses.add(new Option(course.Name, course.Id, null));
    }
    for (Branch__c b : [
      SELECT Id, Name, Branch_Code__c
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      c.branches.add(new Option(b.Name, b.Id, b.Branch_Code__c));
    }
    for (Contact f : faculty()) {
      c.faculty.add(new Option(f.Name, f.Id, f.Title));
    }
    c.canCreateFaculty = Schema.SObjectType.Contact.isCreateable();
    c.canPrice = Schema.SObjectType.Fee_Price__c.isCreateable();
    return c;
  }

  public class BranchChoices {
    @AuraEnabled
    public List<Option> rooms = new List<Option>();
    @AuraEnabled
    public List<Option> teachers = new List<Option>();
  }

  /** Rooms and teachers of a branch. */
  public static BranchChoices branchChoices(Id branchId) {
    BranchChoices c = new BranchChoices();
    for (Room__c r : [
      SELECT Id, Name, Capacity__c, Room_Type__c
      FROM Room__c
      WHERE Branch__c = :branchId AND Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
    ]) {
      c.rooms.add(
        new Option(
          r.Name +
          (r.Capacity__c == null
            ? ''
            : ' (' + r.Capacity__c.intValue() + ' seats)'),
          r.Id,
          String.valueOf(r.Capacity__c)
        )
      );
    }
    Set<Id> seen = new Set<Id>();
    for (Branch_Staff__c s : [
      SELECT User__c, User__r.Name
      FROM Branch_Staff__c
      WHERE Branch__c = :branchId AND Role__c = 'Teacher' AND Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY User__r.Name
    ]) {
      if (seen.add(s.User__c)) {
        c.teachers.add(new Option(s.User__r.Name, s.User__c, null));
      }
    }
    return c;
  }

  // ----------------------------------------------------------------- faculty

  public class FacultyRequest {
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String subject { get; set; }
  }

  /** Faculty are the contacts of the institution's faculty account. */
  public static List<Contact> faculty() {
    Id accountId = facultyAccountId(false);
    if (accountId == null) {
      return new List<Contact>();
    }
    return [
      SELECT Id, Name, Title, Email, Phone
      FROM Contact
      WHERE AccountId = :accountId
      WITH USER_MODE
      ORDER BY LastName, FirstName
      LIMIT 500
    ];
  }

  public static Id createFaculty(FacultyRequest request) {
    if (!Schema.SObjectType.Contact.isCreateable()) {
      throw new AppException('You do not have access to add faculty.');
    }
    if (request == null || String.isBlank(request.lastName)) {
      throw new AppException('Enter the teacher\'s last name.');
    }
    String email = String.isBlank(request.email)
      ? null
      : request.email.trim().toLowerCase();
    Id accountId = facultyAccountId(true);
    if (
      email != null &&
      [
        SELECT COUNT()
        FROM Contact
        WHERE Email = :email AND AccountId = :accountId
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException(
        'A faculty member with ' + email + ' already exists.'
      );
    }
    Contact c = new Contact(
      AccountId = accountId,
      FirstName = String.isBlank(request.firstName)
        ? null
        : request.firstName.trim(),
      LastName = request.lastName.trim(),
      Email = email,
      Phone = request.phone,
      Title = String.isBlank(request.subject)
        ? 'Faculty'
        : 'Faculty – ' + request.subject.trim(),
      Department = 'Academics'
    );
    Database.insert(c, AccessLevel.USER_MODE);
    return c.Id;
  }

  /** "KT Edutech Faculty": the business account that holds faculty contacts. */
  public static String facultyAccountName() {
    return AppSettings.getString('Institution_Name', 'KT Edutech') + ' Faculty';
  }

  /** The faculty account, or null before the first faculty member is added. */
  public static Id facultyAccount() {
    return facultyAccountId(false);
  }

  /** The faculty account; created on first use when create is true. */
  private static Id facultyAccountId(Boolean create) {
    String name = facultyAccountName();
    List<Account> found = [
      SELECT Id
      FROM Account
      WHERE Name = :name
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ];
    if (!found.isEmpty() || !create) {
      return found.isEmpty() ? null : found[0].Id;
    }
    Account a = new Account(Name = name, Industry = 'Education');
    Schema.RecordTypeInfo business = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Business_Account');
    if (business != null) {
      a.RecordTypeId = business.getRecordTypeId();
    }
    Database.insert(a, AccessLevel.SYSTEM_MODE);
    return a.Id;
  }
}
