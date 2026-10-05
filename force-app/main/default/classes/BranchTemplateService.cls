/**
 * Multi-branch support: opens a new branch from an existing one used as a
 * template, and compares branches on their key figures.
 *
 * Cloning copies the branch policies (tax, due days, attendance threshold,
 * delivery modes), rooms, branch-specific prices and discounts, upcoming
 * closures, and the running classes with their weekly patterns. Classes are
 * created as Planned, without teachers, and shifted to the new start date so
 * the new branch can be reviewed before it opens. Everything runs as the
 * user, in one transaction.
 */
public with sharing class BranchTemplateService {
  public static final Set<String> TEMPLATE_CLASS_STATUSES = new Set<String>{
    'Planned',
    'Open',
    'Full',
    'In Progress'
  };
  private static final String LOG_SOURCE = 'BranchTemplateService';

  public class CloneRequest {
    @AuraEnabled
    public Id sourceBranchId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String code { get; set; }
    @AuraEnabled
    public String city { get; set; }
    @AuraEnabled
    public String invoicePrefix { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public Id managerId { get; set; }
    @AuraEnabled
    public Boolean includeRooms { get; set; }
    @AuraEnabled
    public Boolean includePrices { get; set; }
    @AuraEnabled
    public Boolean includeDiscounts { get; set; }
    @AuraEnabled
    public Boolean includeClosures { get; set; }
    @AuraEnabled
    public Boolean includeClasses { get; set; }
    /** First day of the new branch's classes; the source timetable is shifted to it. */
    @AuraEnabled
    public Date classStartDate { get; set; }
  }

  public class Preview {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String invoicePrefix;
    @AuraEnabled
    public Integer rooms = 0;
    @AuraEnabled
    public Integer prices = 0;
    @AuraEnabled
    public Integer discounts = 0;
    @AuraEnabled
    public Integer closures = 0;
    @AuraEnabled
    public Integer classes = 0;
    @AuraEnabled
    public Integer patterns = 0;
    @AuraEnabled
    public Date firstClassStart;
    @AuraEnabled
    public Date suggestedStart;
    @AuraEnabled
    public Boolean canCreate = false;
  }

  public class CloneResult {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public Integer rooms = 0;
    @AuraEnabled
    public Integer prices = 0;
    @AuraEnabled
    public Integer discounts = 0;
    @AuraEnabled
    public Integer closures = 0;
    @AuraEnabled
    public Integer classes = 0;
    @AuraEnabled
    public Integer patterns = 0;
    @AuraEnabled
    public List<String> notes = new List<String>();
  }

  public class BranchKpi {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public Boolean active = true;
    @AuraEnabled
    public Integer rooms = 0;
    @AuraEnabled
    public Integer activeClasses = 0;
    @AuraEnabled
    public Integer plannedClasses = 0;
    @AuraEnabled
    public Decimal capacity = 0;
    @AuraEnabled
    public Decimal seatsTaken = 0;
    @AuraEnabled
    public Decimal fillRate;
    @AuraEnabled
    public Integer learners = 0;
    @AuraEnabled
    public Integer waiting = 0;
    @AuraEnabled
    public Decimal attendanceRate;
    @AuraEnabled
    public Integer openEnquiries = 0;
    @AuraEnabled
    public Decimal outstanding = 0;
    @AuraEnabled
    public Decimal overdue = 0;
    @AuraEnabled
    public Decimal collectedThisMonth = 0;
  }

  public class Overview {
    @AuraEnabled
    public List<BranchKpi> branches = new List<BranchKpi>();
    @AuraEnabled
    public BranchKpi totals = new BranchKpi();
    @AuraEnabled
    public Boolean showFinance = false;
    @AuraEnabled
    public Boolean canCreateBranch = false;
  }

  // ------------------------------------------------------------------ preview

  public static Preview preview(Id sourceBranchId) {
    Branch__c source = loadBranch(sourceBranchId);
    Preview result = new Preview();
    result.branchId = source.Id;
    result.name = source.Name;
    result.code = source.Branch_Code__c;
    result.invoicePrefix = source.Invoice_Prefix__c;
    result.canCreate = Schema.SObjectType.Branch__c.isCreateable();
    result.rooms = rooms(sourceBranchId).size();
    result.prices = prices(sourceBranchId).size();
    result.discounts = discounts(sourceBranchId).size();
    result.closures = closures(sourceBranchId).size();
    List<CourseOffering> classes = classes(sourceBranchId);
    result.classes = classes.size();
    result.patterns = patterns(new Map<Id, CourseOffering>(classes).keySet())
      .size();
    result.firstClassStart = firstStart(classes);
    Date nextMonth = Date.today().addMonths(1).toStartOfMonth();
    result.suggestedStart = result.firstClassStart != null &&
      result.firstClassStart > Date.today()
      ? result.firstClassStart
      : nextMonth;
    return result;
  }

  // ------------------------------------------------------------------ clone

  public static CloneResult cloneBranch(CloneRequest request) {
    validate(request);
    Branch__c source = loadBranch(request.sourceBranchId);
    String code = request.code.trim().toUpperCase();
    String name = request.name.trim();

    CloneResult result = new CloneResult();
    Savepoint sp = Database.setSavepoint();
    try {
      Branch__c branch = new Branch__c(
        Name = name,
        Branch_Code__c = code,
        Active__c = true,
        City__c = blankToNull(request.city),
        Email__c = blankToNull(request.email),
        Phone__c = blankToNull(request.phone),
        Branch_Manager__c = request.managerId,
        Invoice_Prefix__c = request.invoicePrefix.trim().toUpperCase(),
        State__c = source.State__c,
        Country__c = source.Country__c,
        Operating_Hours__c = source.Operating_Hours__c,
        Delivery_Modes__c = source.Delivery_Modes__c,
        Invoice_Due_Days__c = source.Invoice_Due_Days__c,
        Attendance_Threshold__c = source.Attendance_Threshold__c,
        Cancellation_Notice_Hours__c = source.Cancellation_Notice_Hours__c,
        Tax_Rate__c = source.Tax_Rate__c
      );
      insert as user branch;
      result.branchId = branch.Id;
      result.branchName = name;

      Map<Id, Id> roomMap = new Map<Id, Id>();
      if (isTrue(request.includeRooms)) {
        roomMap = cloneRooms(source.Id, branch.Id);
        result.rooms = roomMap.size();
      }
      if (isTrue(request.includePrices)) {
        result.prices = clonePrices(source.Id, branch.Id);
      }
      if (isTrue(request.includeDiscounts)) {
        result.discounts = cloneDiscounts(source.Id, branch.Id, code, result);
      }
      if (isTrue(request.includeClosures)) {
        result.closures = cloneClosures(source.Id, branch.Id);
      }
      if (isTrue(request.includeClasses)) {
        cloneClasses(source, branch, roomMap, request.classStartDate, result);
      }
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
    Logger.info(
      LOG_SOURCE,
      'Branch ' +
        code +
        ' opened from ' +
        source.Branch_Code__c +
        ': ' +
        result.rooms +
        ' rooms, ' +
        result.prices +
        ' prices, ' +
        result.discounts +
        ' discounts, ' +
        result.closures +
        ' closures, ' +
        result.classes +
        ' classes.'
    );
    return result;
  }

  private static void validate(CloneRequest request) {
    if (request == null || request.sourceBranchId == null) {
      throw new AppException('Choose the branch to use as the template.');
    }
    if (!Schema.SObjectType.Branch__c.isCreateable()) {
      throw new AppException('You do not have permission to open branches.');
    }
    if (String.isBlank(request.name)) {
      throw new AppException('Enter the new branch name.');
    }
    if (String.isBlank(request.code)) {
      throw new AppException('Enter a branch code, for example HYD-01.');
    }
    if (String.isBlank(request.invoicePrefix)) {
      throw new AppException(
        'Enter an invoice prefix so the new branch has its own invoice numbers.'
      );
    }
    String code = request.code.trim().toUpperCase();
    String prefix = request.invoicePrefix.trim().toUpperCase();
    for (Branch__c existing : [
      SELECT Name, Branch_Code__c, Invoice_Prefix__c
      FROM Branch__c
      WHERE Branch_Code__c = :code OR Invoice_Prefix__c = :prefix
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      throw new AppException(
        existing.Branch_Code__c == code
          ? 'Branch code ' + code + ' is already used by ' + existing.Name + '.'
          : 'Invoice prefix ' +
            prefix +
            ' is already used by ' +
            existing.Name +
            '.'
      );
    }
    if (isTrue(request.includeClasses) && request.classStartDate == null) {
      throw new AppException('Choose when the new branch\'s classes start.');
    }
  }

  private static Map<Id, Id> cloneRooms(Id sourceId, Id branchId) {
    List<Room__c> sourceRooms = rooms(sourceId);
    List<Room__c> copies = new List<Room__c>();
    for (Room__c room : sourceRooms) {
      copies.add(
        new Room__c(
          Name = room.Name,
          Branch__c = branchId,
          Room_Type__c = room.Room_Type__c,
          Capacity__c = room.Capacity__c,
          Equipment__c = room.Equipment__c,
          Meeting_Url__c = room.Meeting_Url__c,
          Active__c = true
        )
      );
    }
    insert as user copies;
    Map<Id, Id> roomMap = new Map<Id, Id>();
    for (Integer i = 0; i < sourceRooms.size(); i++) {
      roomMap.put(sourceRooms[i].Id, copies[i].Id);
    }
    return roomMap;
  }

  private static Integer clonePrices(Id sourceId, Id branchId) {
    List<Fee_Price__c> copies = new List<Fee_Price__c>();
    for (Fee_Price__c price : prices(sourceId)) {
      copies.add(
        new Fee_Price__c(
          Branch__c = branchId,
          Learning_Course__c = price.Learning_Course__c,
          Fee_Type__c = price.Fee_Type__c,
          Delivery_Mode__c = price.Delivery_Mode__c,
          Billing_Frequency__c = price.Billing_Frequency__c,
          Amount__c = price.Amount__c,
          Effective_From__c = price.Effective_From__c,
          Effective_To__c = price.Effective_To__c,
          Description__c = price.Description__c,
          Active__c = true
        )
      );
    }
    insert as user copies;
    return copies.size();
  }

  private static Integer cloneDiscounts(
    Id sourceId,
    Id branchId,
    String branchCode,
    CloneResult result
  ) {
    List<Discount__c> sourceDiscounts = discounts(sourceId);
    Map<String, Discount__c> byCode = new Map<String, Discount__c>();
    for (Discount__c discount : sourceDiscounts) {
      String newCode = (discount.Code__c +
        '-' +
        branchCode)
        .toUpperCase()
        .replaceAll('[^A-Z0-9-]', '')
        .left(30);
      byCode.put(
        newCode,
        new Discount__c(
          Name = discount.Name,
          Code__c = newCode,
          Applies_To_Branch__c = branchId,
          Applies_To_Course__c = discount.Applies_To_Course__c,
          Discount_Type__c = discount.Discount_Type__c,
          Value__c = discount.Value__c,
          Fee_Type__c = discount.Fee_Type__c,
          Valid_From__c = discount.Valid_From__c,
          Valid_To__c = discount.Valid_To__c,
          Max_Uses__c = discount.Max_Uses__c,
          Requires_Approval__c = discount.Requires_Approval__c,
          Description__c = discount.Description__c,
          Active__c = true
        )
      );
    }
    Set<String> codes = byCode.keySet();
    for (Discount__c taken : [
      SELECT Code__c
      FROM Discount__c
      WHERE Code__c IN :codes
      WITH SYSTEM_MODE
    ]) {
      byCode.remove(taken.Code__c.toUpperCase());
      result.notes.add(
        'Discount code ' + taken.Code__c + ' already exists, so it was skipped.'
      );
    }
    insert as user byCode.values();
    if (!byCode.isEmpty()) {
      result.notes.add(
        'Branch discounts were given new codes ending in -' + branchCode + '.'
      );
    }
    return byCode.size();
  }

  private static Integer cloneClosures(Id sourceId, Id branchId) {
    List<Calendar_Closure__c> copies = new List<Calendar_Closure__c>();
    for (Calendar_Closure__c closure : closures(sourceId)) {
      copies.add(
        new Calendar_Closure__c(
          Name = closure.Name,
          Branch__c = branchId,
          Start_Date__c = closure.Start_Date__c,
          End_Date__c = closure.End_Date__c,
          Closure_Type__c = closure.Closure_Type__c
        )
      );
    }
    insert as user copies;
    return copies.size();
  }

  private static void cloneClasses(
    Branch__c source,
    Branch__c branch,
    Map<Id, Id> roomMap,
    Date startDate,
    CloneResult result
  ) {
    List<CourseOffering> sourceClasses = classes(source.Id);
    if (sourceClasses.isEmpty()) {
      return;
    }
    Date first = firstStart(sourceClasses);
    Integer shift = weeksShift(first, startDate);
    List<CourseOffering> copies = new List<CourseOffering>();
    Boolean hadTeachers = false;
    Boolean missingRooms = false;
    for (CourseOffering offering : sourceClasses) {
      hadTeachers |= offering.Teacher_User__c != null;
      Id room = offering.Room__c == null ? null : roomMap.get(offering.Room__c);
      missingRooms |= offering.Room__c != null && room == null;
      copies.add(
        new CourseOffering(
          Name = className(offering.Name, source, branch),
          LearningCourseId = offering.LearningCourseId,
          Branch__c = branch.Id,
          Room__c = room,
          EnrollmentCapacity = offering.EnrollmentCapacity,
          Delivery_Mode__c = offering.Delivery_Mode__c,
          Class_Status__c = 'Planned',
          StartDate = shifted(offering.StartDate, shift),
          EndDate = shifted(offering.EndDate, shift)
        )
      );
    }
    insert as user copies;
    Map<Id, Id> classMap = new Map<Id, Id>();
    for (Integer i = 0; i < sourceClasses.size(); i++) {
      classMap.put(sourceClasses[i].Id, copies[i].Id);
    }
    result.classes = copies.size();

    List<CourseOfferingSchedule> patternCopies = new List<CourseOfferingSchedule>();
    for (CourseOfferingSchedule pattern : patterns(classMap.keySet())) {
      CourseOfferingSchedule copy = new CourseOfferingSchedule(
        CourseOfferingId = classMap.get(pattern.CourseOfferingId),
        Description = pattern.Description,
        StartTime = pattern.StartTime,
        EndTime = pattern.EndTime,
        IsMonday = pattern.IsMonday,
        IsTuesday = pattern.IsTuesday,
        IsWednesday = pattern.IsWednesday,
        IsThursday = pattern.IsThursday,
        IsFriday = pattern.IsFriday,
        IsSaturday = pattern.IsSaturday,
        IsSunday = pattern.IsSunday,
        Type = pattern.Type
      );
      // Only fields with a value are set: user-mode DML checks every field put on the record.
      if (pattern.StartDate != null) {
        copy.StartDate = pattern.StartDate.addDays(shift);
      }
      if (pattern.EndDate != null) {
        copy.EndDate = pattern.EndDate.addDays(shift);
      }
      patternCopies.add(copy);
    }
    insert as user patternCopies;
    result.patterns = patternCopies.size();

    result.notes.add(
      'Classes were created as Planned. Review them, then generate sessions and open them for enrolment.'
    );
    if (hadTeachers) {
      result.notes.add('Assign teachers to the new classes.');
    }
    if (missingRooms) {
      result.notes.add(
        'Rooms were not copied, so the classes have no default room.'
      );
    }
  }

  @TestVisible
  private static String className(
    String original,
    Branch__c source,
    Branch__c branch
  ) {
    String name = original;
    if (String.isNotBlank(source.Name) && name.contains(source.Name)) {
      name = name.replace(source.Name, branch.Name);
    } else if (
      String.isNotBlank(source.Branch_Code__c) &&
      name.contains(source.Branch_Code__c)
    ) {
      name = name.replace(source.Branch_Code__c, branch.Branch_Code__c);
    } else {
      name = name + ' · ' + branch.Branch_Code__c;
    }
    return name.left(80);
  }

  // ------------------------------------------------------------------ KPIs

  public static Overview overview() {
    Overview result = new Overview();
    result.canCreateBranch = Schema.SObjectType.Branch__c.isCreateable();
    Map<Id, BranchKpi> byId = new Map<Id, BranchKpi>();
    for (Branch__c branch : [
      SELECT Id, Name, Branch_Code__c, City__c, Active__c
      FROM Branch__c
      WITH USER_MODE
      ORDER BY Active__c DESC, Name
      LIMIT 200
    ]) {
      BranchKpi kpi = new BranchKpi();
      kpi.branchId = branch.Id;
      kpi.name = branch.Name;
      kpi.code = branch.Branch_Code__c;
      kpi.city = branch.City__c;
      kpi.active = branch.Active__c;
      byId.put(branch.Id, kpi);
      result.branches.add(kpi);
    }
    if (byId.isEmpty()) {
      return result;
    }
    Set<Id> ids = byId.keySet();
    if (readable(Room__c.SObjectType)) {
      for (AggregateResult row : [
        SELECT Branch__c branch, COUNT(Id) total
        FROM Room__c
        WHERE Branch__c IN :ids AND Active__c = TRUE
        WITH USER_MODE
        GROUP BY Branch__c
      ]) {
        kpiFor(byId, row).rooms = (Integer) row.get('total');
      }
    }
    if (readable(CourseOffering.SObjectType)) {
      classKpis(byId, ids);
    }
    if (readable(CourseOfferingParticipant.SObjectType)) {
      for (AggregateResult row : [
        SELECT Branch__c branch, COUNT_DISTINCT(ParticipantContactId) total
        FROM CourseOfferingParticipant
        WHERE
          Branch__c IN :ids
          AND ParticipationStatus IN :SeatService.SEAT_STATUSES
        WITH USER_MODE
        GROUP BY Branch__c
      ]) {
        kpiFor(byId, row).learners = (Integer) row.get('total');
      }
    }
    if (readable(Session_Attendance__c.SObjectType)) {
      attendanceKpis(byId, ids);
    }
    if (readable(Lead.SObjectType)) {
      for (AggregateResult row : [
        SELECT Branch__c branch, COUNT(Id) total
        FROM Lead
        WHERE
          Branch__c IN :ids
          AND IsConverted = FALSE
          AND Status != 'Unqualified'
        WITH USER_MODE
        GROUP BY Branch__c
      ]) {
        kpiFor(byId, row).openEnquiries = (Integer) row.get('total');
      }
    }
    if (
      readable(Student_Invoice__c.SObjectType) &&
      readable(Student_Payment__c.SObjectType)
    ) {
      result.showFinance = true;
      financeKpis(byId, ids);
    }
    totals(result);
    return result;
  }

  private static void classKpis(Map<Id, BranchKpi> byId, Set<Id> ids) {
    for (AggregateResult row : [
      SELECT
        Branch__c branch,
        Class_Status__c status,
        COUNT(Id) total,
        SUM(EnrollmentCapacity) capacity,
        SUM(Seats_Taken__c) taken,
        SUM(Waitlist_Count__c) waiting
      FROM CourseOffering
      WHERE Branch__c IN :ids AND Class_Status__c IN :TEMPLATE_CLASS_STATUSES
      WITH USER_MODE
      GROUP BY Branch__c, Class_Status__c
    ]) {
      BranchKpi kpi = kpiFor(byId, row);
      Integer total = (Integer) row.get('total');
      if ((String) row.get('status') == 'Planned') {
        kpi.plannedClasses += total;
        continue;
      }
      kpi.activeClasses += total;
      kpi.capacity += nvl((Decimal) row.get('capacity'));
      kpi.seatsTaken += nvl((Decimal) row.get('taken'));
      kpi.waiting += nvl((Decimal) row.get('waiting')).intValue();
    }
    for (BranchKpi kpi : byId.values()) {
      kpi.fillRate = rate(kpi.seatsTaken, kpi.capacity);
    }
  }

  private static void attendanceKpis(Map<Id, BranchKpi> byId, Set<Id> ids) {
    Datetime since = System.now().addDays(-30);
    Map<Id, Decimal[]> counts = new Map<Id, Decimal[]>();
    for (AggregateResult row : [
      SELECT
        Class_Session__r.Branch__c branch,
        Status__c status,
        COUNT(Id) total
      FROM Session_Attendance__c
      WHERE
        Class_Session__r.Branch__c IN :ids
        AND Class_Session__r.Start__c >= :since
        AND Status__c IN ('Present', 'Late', 'Absent')
      WITH USER_MODE
      GROUP BY Class_Session__r.Branch__c, Status__c
    ]) {
      Id branchId = (Id) row.get('branch');
      if (!counts.containsKey(branchId)) {
        counts.put(branchId, new List<Decimal>{ 0, 0 });
      }
      Decimal total = (Integer) row.get('total');
      Decimal[] pair = counts.get(branchId);
      pair[1] += total;
      if ((String) row.get('status') != 'Absent') {
        pair[0] += total;
      }
    }
    for (Id branchId : counts.keySet()) {
      Decimal[] pair = counts.get(branchId);
      byId.get(branchId).attendanceRate = rate(pair[0], pair[1]);
    }
  }

  private static void financeKpis(Map<Id, BranchKpi> byId, Set<Id> ids) {
    for (AggregateResult row : [
      SELECT Branch__c branch, Overdue__c overdue, SUM(Balance_Due__c) balance
      FROM Student_Invoice__c
      WHERE Branch__c IN :ids AND Status__c IN :BillingService.OPEN_STATUSES
      WITH USER_MODE
      GROUP BY Branch__c, Overdue__c
    ]) {
      BranchKpi kpi = kpiFor(byId, row);
      Decimal balance = nvl((Decimal) row.get('balance'));
      kpi.outstanding += balance;
      if ((Boolean) row.get('overdue')) {
        kpi.overdue += balance;
      }
    }
    Date monthStart = Date.today().toStartOfMonth();
    for (AggregateResult row : [
      SELECT Branch__c branch, SUM(Amount__c) total
      FROM Student_Payment__c
      WHERE
        Branch__c IN :ids
        AND Status__c = 'Confirmed'
        AND Method__c != :CreditService.CREDIT_METHOD
        AND Payment_Date__c >= :monthStart
      WITH USER_MODE
      GROUP BY Branch__c
    ]) {
      kpiFor(byId, row).collectedThisMonth = nvl((Decimal) row.get('total'));
    }
  }

  private static void totals(Overview result) {
    BranchKpi sum = result.totals;
    sum.name = 'All branches';
    Decimal attendanceWeighted = 0;
    Decimal attendanceWeight = 0;
    for (BranchKpi kpi : result.branches) {
      sum.rooms += kpi.rooms;
      sum.activeClasses += kpi.activeClasses;
      sum.plannedClasses += kpi.plannedClasses;
      sum.capacity += kpi.capacity;
      sum.seatsTaken += kpi.seatsTaken;
      sum.learners += kpi.learners;
      sum.waiting += kpi.waiting;
      sum.openEnquiries += kpi.openEnquiries;
      sum.outstanding += kpi.outstanding;
      sum.overdue += kpi.overdue;
      sum.collectedThisMonth += kpi.collectedThisMonth;
      if (kpi.attendanceRate != null && kpi.seatsTaken > 0) {
        attendanceWeighted += kpi.attendanceRate * kpi.seatsTaken;
        attendanceWeight += kpi.seatsTaken;
      }
    }
    sum.fillRate = rate(sum.seatsTaken, sum.capacity);
    sum.attendanceRate = attendanceWeight == 0
      ? null
      : (attendanceWeighted / attendanceWeight).setScale(1);
  }

  // ------------------------------------------------------------------ queries

  private static Branch__c loadBranch(Id branchId) {
    List<Branch__c> rows = [
      SELECT
        Id,
        Name,
        Branch_Code__c,
        Invoice_Prefix__c,
        State__c,
        Country__c,
        Operating_Hours__c,
        Delivery_Modes__c,
        Invoice_Due_Days__c,
        Attendance_Threshold__c,
        Cancellation_Notice_Hours__c,
        Tax_Rate__c
      FROM Branch__c
      WHERE Id = :branchId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('The template branch was not found.');
    }
    return rows[0];
  }

  private static List<Room__c> rooms(Id branchId) {
    return [
      SELECT Id, Name, Room_Type__c, Capacity__c, Equipment__c, Meeting_Url__c
      FROM Room__c
      WHERE Branch__c = :branchId AND Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
    ];
  }

  private static List<Fee_Price__c> prices(Id branchId) {
    Date today = Date.today();
    return [
      SELECT
        Learning_Course__c,
        Fee_Type__c,
        Delivery_Mode__c,
        Billing_Frequency__c,
        Amount__c,
        Effective_From__c,
        Effective_To__c,
        Description__c
      FROM Fee_Price__c
      WHERE
        Branch__c = :branchId
        AND Active__c = TRUE
        AND (Effective_To__c = NULL
        OR Effective_To__c >= :today)
      WITH USER_MODE
    ];
  }

  private static List<Discount__c> discounts(Id branchId) {
    Date today = Date.today();
    return [
      SELECT
        Name,
        Code__c,
        Applies_To_Course__c,
        Discount_Type__c,
        Value__c,
        Fee_Type__c,
        Valid_From__c,
        Valid_To__c,
        Max_Uses__c,
        Requires_Approval__c,
        Description__c
      FROM Discount__c
      WHERE
        Applies_To_Branch__c = :branchId
        AND Active__c = TRUE
        AND (Valid_To__c = NULL
        OR Valid_To__c >= :today)
      WITH USER_MODE
    ];
  }

  private static List<Calendar_Closure__c> closures(Id branchId) {
    Date today = Date.today();
    return [
      SELECT Name, Start_Date__c, End_Date__c, Closure_Type__c
      FROM Calendar_Closure__c
      WHERE Branch__c = :branchId AND End_Date__c >= :today
      WITH USER_MODE
    ];
  }

  private static List<CourseOffering> classes(Id branchId) {
    return [
      SELECT
        Id,
        Name,
        LearningCourseId,
        Room__c,
        Teacher_User__c,
        EnrollmentCapacity,
        Delivery_Mode__c,
        StartDate,
        EndDate
      FROM CourseOffering
      WHERE
        Branch__c = :branchId
        AND Class_Status__c IN :TEMPLATE_CLASS_STATUSES
      WITH USER_MODE
      ORDER BY Name
      LIMIT 500
    ];
  }

  private static List<CourseOfferingSchedule> patterns(Set<Id> classIds) {
    return [
      SELECT
        CourseOfferingId,
        Description,
        StartTime,
        EndTime,
        StartDate,
        EndDate,
        IsMonday,
        IsTuesday,
        IsWednesday,
        IsThursday,
        IsFriday,
        IsSaturday,
        IsSunday,
        Type
      FROM CourseOfferingSchedule
      WHERE CourseOfferingId IN :classIds
      WITH USER_MODE
    ];
  }

  // ------------------------------------------------------------------ helpers

  private static Date firstStart(List<CourseOffering> classes) {
    Date first;
    for (CourseOffering offering : classes) {
      if (offering.StartDate == null) {
        continue;
      }
      Date day = offering.StartDate.date();
      if (first == null || day < first) {
        first = day;
      }
    }
    return first;
  }

  /**
   * Days to move the timetable, in whole weeks so every class keeps its
   * weekday; the first class lands on or after the chosen start date.
   */
  @TestVisible
  private static Integer weeksShift(Date first, Date startDate) {
    if (first == null || startDate == null) {
      return 0;
    }
    Integer days = first.daysBetween(startDate);
    return days >= 0 ? ((days + 6) / 7) * 7 : (days / 7) * 7;
  }

  private static Datetime shifted(Datetime value, Integer days) {
    return value == null ? null : value.addDays(days);
  }

  private static BranchKpi kpiFor(
    Map<Id, BranchKpi> byId,
    AggregateResult row
  ) {
    return byId.get((Id) row.get('branch'));
  }

  private static Decimal rate(Decimal part, Decimal whole) {
    return whole == null ||
      whole == 0
      ? null
      : (nvl(part) / whole * 100).setScale(1);
  }

  private static Boolean isTrue(Boolean value) {
    return value == true;
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  private static Boolean readable(SObjectType type) {
    return type.getDescribe().isAccessible();
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
