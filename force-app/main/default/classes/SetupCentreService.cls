/**
 * Set-up Centre (Home page): one place to create and review the institution's
 * set-up records (branches, rooms, staff roles, courses, classes, holidays,
 * discounts, faculty, portal access) and the gaps that stop the timetable,
 * billing or the portal from working (for example a class without a teacher).
 *
 * Counts and gaps run in user mode, so each person sees their own records
 * (a branch manager sees their branches). Tiles show only for objects the user
 * can read; "New" only where they can create.
 */
public with sharing class SetupCentreService {
  private static final Set<String> RUNNING = new Set<String>{
    'Open',
    'In Progress',
    'Full'
  };
  private static final Set<String> CURRENT = new Set<String>{
    'Planned',
    'Open',
    'In Progress',
    'Full'
  };
  @TestVisible
  private static final Integer SAMPLE = 5;

  public class Tile {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String listView;
    @AuraEnabled
    public Boolean canCreate = false;
    @AuraEnabled
    public String createLabel;
    /** True when "New" opens the guided screen; false means the standard record form. */
    @AuraEnabled
    public Boolean wizard = false;
    /** A second action on the tile (Manage staff). */
    @AuraEnabled
    public String manageLabel;
    /** A record that lists this tile's records (the faculty account). */
    @AuraEnabled
    public Id listRecordId;
  }

  public class RecordRef {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  public class Gap {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String advice;
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public List<RecordRef> records = new List<RecordRef>();
  }

  public class Centre {
    @AuraEnabled
    public List<Tile> tiles = new List<Tile>();
    @AuraEnabled
    public List<Gap> gaps = new List<Gap>();
    @AuraEnabled
    public Integer openGaps = 0;
  }

  public static Centre centre() {
    if (!canUse()) {
      throw new AppException('You do not have access to the Set-up Centre.');
    }
    Centre result = new Centre();
    Date today = Date.today();

    if (readable(Branch__c.SObjectType)) {
      Tile t = tile(
        'branches',
        'Branches',
        'custom:custom24',
        Branch__c.SObjectType,
        'New branch',
        'All'
      );
      t.count = [
        SELECT COUNT()
        FROM Branch__c
        WHERE Active__c = TRUE
        WITH USER_MODE
      ];
      Integer inactive = [
        SELECT COUNT()
        FROM Branch__c
        WHERE Active__c = FALSE
        WITH USER_MODE
      ];
      t.detail = inactive == 0 ? 'All active' : inactive + ' inactive';
      t.wizard = t.canCreate;
      result.tiles.add(t);
    }
    if (readable(Room__c.SObjectType)) {
      Tile t = tile(
        'rooms',
        'Rooms',
        'custom:custom16',
        Room__c.SObjectType,
        'New room',
        'All'
      );
      AggregateResult seats = [
        SELECT COUNT(Id) n, SUM(Capacity__c) seats
        FROM Room__c
        WHERE Active__c = TRUE
        WITH USER_MODE
      ];
      t.count = (Integer) seats.get('n');
      t.detail = nvl((Decimal) seats.get('seats')).intValue() + ' seats';
      t.wizard = t.canCreate;
      result.tiles.add(t);
    }
    if (readable(Branch_Staff__c.SObjectType)) {
      Tile t = tile(
        'staff',
        'Staff roles',
        'standard:people',
        Branch_Staff__c.SObjectType,
        'Add staff role',
        'All'
      );
      Set<Id> people = new Set<Id>();
      for (Branch_Staff__c s : [
        SELECT User__c
        FROM Branch_Staff__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        LIMIT 2000
      ]) {
        t.count++;
        people.add(s.User__c);
      }
      t.detail = people.size() + (people.size() == 1 ? ' person' : ' people');
      if (StaffSetupService.canManage()) {
        // Administrators add the login and its roles together; "Manage staff" changes roles.
        t.canCreate = true;
        t.wizard = true;
        t.createLabel = 'Add staff member';
        t.manageLabel = 'Manage staff';
      }
      result.tiles.add(t);
    }
    if (readable(LearningCourse.SObjectType)) {
      Tile t = tile(
        'courses',
        'Courses',
        'standard:education',
        LearningCourse.SObjectType,
        'New course',
        null
      );
      t.count = [
        SELECT COUNT()
        FROM LearningCourse
        WHERE IsActive = TRUE
        WITH USER_MODE
      ];
      t.detail = 'Active courses';
      t.wizard =
        t.canCreate && Learning.SObjectType.getDescribe().isCreateable();
      result.tiles.add(t);
    }
    Map<String, Integer> byStatus = new Map<String, Integer>();
    if (readable(CourseOffering.SObjectType)) {
      Tile t = tile(
        'classes',
        'Classes',
        'standard:event',
        CourseOffering.SObjectType,
        'New class',
        null
      );
      for (AggregateResult row : [
        SELECT Class_Status__c status, COUNT(Id) n
        FROM CourseOffering
        WHERE Class_Status__c IN :CURRENT
        WITH USER_MODE
        GROUP BY Class_Status__c
      ]) {
        byStatus.put((String) row.get('status'), (Integer) row.get('n'));
        t.count += (Integer) row.get('n');
      }
      Integer running =
        nvlInt(byStatus.get('Open')) +
        nvlInt(byStatus.get('In Progress')) +
        nvlInt(byStatus.get('Full'));
      t.detail =
        running +
        ' running · ' +
        nvlInt(byStatus.get('Planned')) +
        ' planned';
      t.wizard =
        t.canCreate &&
        CourseOfferingSchedule.SObjectType.getDescribe().isCreateable() &&
        LearningCourse.SObjectType.getDescribe().isAccessible();
      result.tiles.add(t);
    }
    if (readable(Calendar_Closure__c.SObjectType)) {
      Tile t = tile(
        'holidays',
        'Holidays',
        'standard:date_input',
        Calendar_Closure__c.SObjectType,
        'New holiday',
        'All'
      );
      List<Calendar_Closure__c> next = [
        SELECT Name, Start_Date__c
        FROM Calendar_Closure__c
        WHERE End_Date__c >= :today
        WITH USER_MODE
        ORDER BY Start_Date__c
        LIMIT 1
      ];
      t.count = [
        SELECT COUNT()
        FROM Calendar_Closure__c
        WHERE End_Date__c >= :today
        WITH USER_MODE
      ];
      t.detail = next.isEmpty()
        ? 'None coming up'
        : 'Next: ' + next[0].Name + ', ' + next[0].Start_Date__c.format();
      t.wizard = t.canCreate;
      result.tiles.add(t);
    }
    if (readable(Discount__c.SObjectType)) {
      Tile t = tile(
        'discounts',
        'Discounts',
        'standard:pricebook',
        Discount__c.SObjectType,
        'New discount',
        'All'
      );
      t.count = [
        SELECT COUNT()
        FROM Discount__c
        WHERE Active__c = TRUE AND (Valid_To__c = NULL OR Valid_To__c >= :today)
        WITH USER_MODE
      ];
      t.detail = 'Active codes';
      t.wizard = t.canCreate;
      if (Schema.SObjectType.Discount__c.isUpdateable()) {
        t.manageLabel = 'Manage discounts';
      }
      result.tiles.add(t);
    }
    if (readable(CourseOffering.SObjectType)) {
      Tile t = tile(
        'faculty',
        'Faculty',
        'standard:avatar',
        Contact.SObjectType,
        null,
        null
      );
      t.createLabel = 'New faculty';
      t.canCreate =
        Contact.SObjectType.getDescribe().isCreateable() &&
        CourseOffering.SObjectType.getDescribe().isCreateable();
      t.wizard = t.canCreate;
      t.listRecordId = CatalogSetupService.facultyAccount();
      t.objectApiName = null; // "View all" opens the faculty account, not every contact
      Set<Id> faculty = new Set<Id>();
      for (AggregateResult row : [
        SELECT PrimaryFacultyId f
        FROM CourseOffering
        WHERE Class_Status__c IN :CURRENT AND PrimaryFacultyId != NULL
        WITH USER_MODE
        GROUP BY PrimaryFacultyId
      ]) {
        faculty.add((Id) row.get('f'));
      }
      t.count = faculty.size();
      t.detail = 'Teaching current classes';
      result.tiles.add(t);
    }
    Tile portal = portalTile();
    if (portal != null) {
      result.tiles.add(portal);
    }

    addGaps(result, today);
    for (Gap g : result.gaps) {
      if (g.count > 0) {
        result.openGaps++;
      }
    }
    return result;
  }

  /** Administrators, branch managers and academic coordinators: anyone who can set up rooms or classes. */
  public static Boolean canUse() {
    return Schema.SObjectType.Room__c.isCreateable() ||
      Schema.SObjectType.Branch__c.isCreateable() ||
      Schema.SObjectType.CourseOffering.isCreateable();
  }

  // ------------------------------------------------------------------ gaps

  private static void addGaps(Centre result, Date today) {
    if (readable(Branch__c.SObjectType) && readable(Room__c.SObjectType)) {
      Set<Id> withRooms = new Set<Id>();
      for (AggregateResult row : [
        SELECT Branch__c b
        FROM Room__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        GROUP BY Branch__c
      ]) {
        withRooms.add((Id) row.get('b'));
      }
      Gap g = gap(
        'branchRooms',
        'Branches without rooms',
        'Click a branch to add its rooms, so classes and exams can be seated.'
      );
      fill(
        g,
        [
          SELECT Id, Name
          FROM Branch__c
          WHERE Active__c = TRUE AND Id NOT IN :withRooms
          WITH USER_MODE
          ORDER BY Name
          LIMIT 200
        ]
      );
      result.gaps.add(g);

      Gap m = gap(
        'branchManager',
        'Branches without a branch manager',
        'Open the branch → Edit → Branch Manager (KTEdutech section); they approve refunds and see the branch desks.'
      );
      fill(
        m,
        [
          SELECT Id, Name
          FROM Branch__c
          WHERE Active__c = TRUE AND Branch_Manager__c = NULL
          WITH USER_MODE
          ORDER BY Name
          LIMIT 200
        ]
      );
      result.gaps.add(m);
    }
    if (
      readable(LearningCourse.SObjectType) && readable(Fee_Price__c.SObjectType)
    ) {
      Set<Id> priced = new Set<Id>();
      for (AggregateResult row : [
        SELECT Learning_Course__c c
        FROM Fee_Price__c
        WHERE
          Active__c = TRUE
          AND Fee_Type__c = 'Tuition'
          AND Effective_From__c <= :today
          AND (Effective_To__c = NULL
          OR Effective_To__c >= :today)
        WITH USER_MODE
        GROUP BY Learning_Course__c
      ]) {
        priced.add((Id) row.get('c'));
      }
      Gap g = gap(
        'coursePrice',
        'Courses without a tuition price',
        'Enrolments in these courses would be free. Open the course → Course pricing → add a tuition price.'
      );
      fill(
        g,
        [
          SELECT Id, Name
          FROM LearningCourse
          WHERE IsActive = TRUE AND Id NOT IN :priced
          WITH USER_MODE
          ORDER BY Name
          LIMIT 200
        ]
      );
      result.gaps.add(g);
    }
    if (!readable(CourseOffering.SObjectType)) {
      return;
    }
    Gap teacher = gap(
      'classTeacher',
      'Classes without a teacher',
      'Click a class to choose its teacher (login) and faculty; the upcoming sessions follow.'
    );
    fill(
      teacher,
      [
        SELECT Id, Name
        FROM CourseOffering
        WHERE
          Class_Status__c IN :CURRENT
          AND Teacher_User__c = NULL
          AND PrimaryFacultyId = NULL
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]
    );
    result.gaps.add(teacher);

    Gap branch = gap(
      'classBranch',
      'Classes without a branch',
      'Click a class to choose its branch: prices, invoices and the branch desks depend on it.'
    );
    fill(
      branch,
      [
        SELECT Id, Name
        FROM CourseOffering
        WHERE Class_Status__c IN :CURRENT AND Branch__c = NULL
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]
    );
    result.gaps.add(branch);

    Gap room = gap(
      'classRoom',
      'Classroom classes without a room',
      'Click a class to choose a room so the timetable can check clashes and capacity.'
    );
    fill(
      room,
      [
        SELECT Id, Name
        FROM CourseOffering
        WHERE
          Class_Status__c IN :CURRENT
          AND Room__c = NULL
          AND Delivery_Mode__c IN ('Classroom', 'Hybrid')
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]
    );
    result.gaps.add(room);

    Gap seats = gap(
      'classSeats',
      'Classes without a seat limit',
      'Click a class to set its seats: without a limit it can never be full or have a waitlist.'
    );
    fill(
      seats,
      [
        SELECT Id, Name
        FROM CourseOffering
        WHERE Class_Status__c IN :CURRENT AND EnrollmentCapacity = NULL
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]
    );
    result.gaps.add(seats);

    if (readable(Class_Session__c.SObjectType)) {
      Set<Id> scheduled = new Set<Id>();
      for (AggregateResult row : [
        SELECT Course_Offering__c c
        FROM Class_Session__c
        WHERE
          Start__c >= :Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0))
          AND Status__c != 'Cancelled'
        WITH USER_MODE
        GROUP BY Course_Offering__c
      ]) {
        scheduled.add((Id) row.get('c'));
      }
      Gap sessions = gap(
        'classSessions',
        'Running classes with no upcoming sessions',
        'Open the class → class menu → Add weekly pattern → Generate sessions, or close the class.'
      );
      fill(
        sessions,
        [
          SELECT Id, Name
          FROM CourseOffering
          WHERE Class_Status__c IN :RUNNING AND Id NOT IN :scheduled
          WITH USER_MODE
          ORDER BY Name
          LIMIT 200
        ]
      );
      result.gaps.add(sessions);
    }
  }

  // --------------------------------------------------------------- helpers

  private static Tile portalTile() {
    if (!Schema.SObjectType.User.isAccessible()) {
      return null;
    }
    Tile t = tile(
      'portal',
      'Portal access',
      'standard:portal',
      User.SObjectType,
      null,
      null
    );
    t.objectApiName = null; // logins are listed per family, not as a list view
    if (PortalAccessService.canGive()) {
      t.canCreate = true;
      t.wizard = true;
      t.createLabel = 'Give portal access';
    }
    t.count = [
      SELECT COUNT()
      FROM User
      WHERE IsActive = TRUE AND ContactId != NULL AND UserType != 'Guest'
      WITH SYSTEM_MODE
    ];
    t.detail = 'Families signed up';
    List<UserLicense> licences = [
      SELECT TotalLicenses, UsedLicenses
      FROM UserLicense
      WHERE Name = 'Customer Community Plus'
      WITH SYSTEM_MODE
    ];
    if (!licences.isEmpty()) {
      t.detail +=
        ' · ' +
        (licences[0].TotalLicenses - licences[0].UsedLicenses) +
        ' licences free';
    }
    return t;
  }

  private static Tile tile(
    String key,
    String label,
    String icon,
    SObjectType type,
    String createLabel,
    String listView
  ) {
    Tile t = new Tile();
    t.key = key;
    t.label = label;
    t.icon = icon;
    t.objectApiName = type.getDescribe().getName();
    t.listView = listView;
    t.createLabel = createLabel;
    t.canCreate = createLabel != null && type.getDescribe().isCreateable();
    return t;
  }

  private static Gap gap(String key, String label, String advice) {
    Gap g = new Gap();
    g.key = key;
    g.label = label;
    g.advice = advice;
    return g;
  }

  private static void fill(Gap g, List<SObject> rows) {
    g.count = rows.size();
    for (SObject row : rows) {
      if (g.records.size() == SAMPLE) {
        break;
      }
      RecordRef ref = new RecordRef();
      ref.id = row.Id;
      ref.name = (String) row.get('Name');
      g.records.add(ref);
    }
  }

  private static Boolean readable(SObjectType type) {
    return type.getDescribe().isAccessible();
  }

  private static Integer nvlInt(Integer value) {
    return value == null ? 0 : value;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
