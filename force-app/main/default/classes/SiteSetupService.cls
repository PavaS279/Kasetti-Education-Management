/**
 * Guided set-up of centres (Phase 5 stage 2): a new branch with its policies,
 * rooms and the year's holidays in one step; rooms added in bulk; holidays
 * added to one or more branches, including a suggested list for the year.
 *
 * Everything saves in user mode, so a person only creates what their
 * permission sets allow (administrators open branches; branch managers and
 * coordinators add rooms and holidays). Duplicate checks run in system mode.
 */
public with sharing class SiteSetupService {
  // ------------------------------------------------------------------ rooms

  public class RoomLine {
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String roomType { get; set; }
    @AuraEnabled
    public Integer capacity { get; set; }
    @AuraEnabled
    public String equipment { get; set; }
    @AuraEnabled
    public String meetingUrl { get; set; }
  }

  /** Adds rooms to a branch; names must be unique at the branch. */
  public static Integer addRooms(Id branchId, List<RoomLine> lines) {
    if (!Schema.SObjectType.Room__c.isCreateable()) {
      throw new AppException('You do not have access to add rooms.');
    }
    if (branchId == null) {
      throw new AppException('Choose the branch.');
    }
    List<Room__c> rooms = buildRooms(branchId, lines);
    Database.insert(rooms, AccessLevel.USER_MODE);
    return rooms.size();
  }

  private static List<Room__c> buildRooms(Id branchId, List<RoomLine> lines) {
    Set<String> taken = new Set<String>();
    if (branchId != null) {
      for (Room__c r : [
        SELECT Name
        FROM Room__c
        WHERE Branch__c = :branchId
        WITH SYSTEM_MODE
      ]) {
        taken.add(r.Name.toLowerCase());
      }
    }
    List<Room__c> rooms = new List<Room__c>();
    for (RoomLine line : lines == null ? new List<RoomLine>() : lines) {
      String name = line.name == null ? '' : line.name.trim();
      if (String.isBlank(name)) {
        continue;
      }
      if (!taken.add(name.toLowerCase())) {
        throw new AppException(
          'There is already a room called ' + name + ' at this branch.'
        );
      }
      String type = String.isBlank(line.roomType) ? 'Classroom' : line.roomType;
      if (line.capacity == null || line.capacity < 1) {
        throw new AppException('Enter the number of seats in ' + name + '.');
      }
      if (type == 'Virtual' && String.isBlank(line.meetingUrl)) {
        throw new AppException(
          'Enter the meeting link for ' + name + ' (virtual rooms need one).'
        );
      }
      rooms.add(
        new Room__c(
          Name = name.left(80),
          Branch__c = branchId,
          Room_Type__c = type,
          Capacity__c = line.capacity,
          Equipment__c = String.isBlank(line.equipment)
            ? null
            : line.equipment.trim(),
          Meeting_Url__c = String.isBlank(line.meetingUrl)
            ? null
            : line.meetingUrl.trim(),
          Active__c = true
        )
      );
    }
    if (rooms.isEmpty()) {
      throw new AppException('Enter at least one room name.');
    }
    return rooms;
  }

  // --------------------------------------------------------------- holidays

  public class HolidayLine {
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public Date startDate { get; set; }
    @AuraEnabled
    public Date endDate { get; set; }
    @AuraEnabled
    public String closureType { get; set; }
    /** Festival dates move each year: shown as "check the date". */
    @AuraEnabled
    public Boolean checkDate { get; set; }
  }

  public class HolidayResult {
    @AuraEnabled
    public Integer created = 0;
    @AuraEnabled
    public Integer skipped = 0;
  }

  /**
   * Adds the holidays to every chosen branch. A holiday the branch already
   * has (same name and first day) is skipped, so the list can be re-applied.
   */
  public static HolidayResult addHolidays(
    List<Id> branchIds,
    List<HolidayLine> lines
  ) {
    if (!Schema.SObjectType.Calendar_Closure__c.isCreateable()) {
      throw new AppException('You do not have access to add holidays.');
    }
    if (branchIds == null || branchIds.isEmpty()) {
      throw new AppException('Choose at least one branch.');
    }
    HolidayResult result = new HolidayResult();
    List<Calendar_Closure__c> rows = buildHolidays(
      new Set<Id>(branchIds),
      lines,
      result
    );
    Database.insert(rows, AccessLevel.USER_MODE);
    result.created = rows.size();
    return result;
  }

  private static List<Calendar_Closure__c> buildHolidays(
    Set<Id> branchIds,
    List<HolidayLine> lines,
    HolidayResult result
  ) {
    List<HolidayLine> valid = new List<HolidayLine>();
    for (HolidayLine h : lines == null ? new List<HolidayLine>() : lines) {
      if (String.isBlank(h.name)) {
        continue;
      }
      if (h.startDate == null) {
        throw new AppException('Enter the date of ' + h.name.trim() + '.');
      }
      if (h.endDate != null && h.endDate < h.startDate) {
        throw new AppException(h.name.trim() + ' cannot end before it starts.');
      }
      valid.add(h);
    }
    if (valid.isEmpty()) {
      throw new AppException('Add at least one holiday.');
    }
    Set<String> existing = new Set<String>();
    for (Calendar_Closure__c c : [
      SELECT Branch__c, Name, Start_Date__c
      FROM Calendar_Closure__c
      WHERE Branch__c IN :branchIds
      WITH SYSTEM_MODE
    ]) {
      existing.add(key(c.Branch__c, c.Name, c.Start_Date__c));
    }
    List<Calendar_Closure__c> rows = new List<Calendar_Closure__c>();
    for (Id branchId : branchIds) {
      for (HolidayLine h : valid) {
        String name = h.name.trim();
        if (!existing.add(key(branchId, name, h.startDate))) {
          result.skipped++;
          continue;
        }
        rows.add(
          new Calendar_Closure__c(
            Name = name.left(80),
            Branch__c = branchId,
            Start_Date__c = h.startDate,
            End_Date__c = h.endDate == null ? h.startDate : h.endDate,
            Closure_Type__c = String.isBlank(h.closureType)
              ? 'Public Holiday'
              : h.closureType
          )
        );
      }
    }
    return rows;
  }

  private static String key(Id branchId, String name, Date day) {
    return branchId + '|' + name.trim().toLowerCase() + '|' + day;
  }

  /**
   * A starting list of Karnataka holidays and usual term breaks for the year.
   * Fixed-date holidays are exact; festival dates follow the lunar calendar,
   * are given for 2026 and 2027 and are marked "check the date" against the
   * state government's published list.
   */
  public static List<HolidayLine> suggestedHolidays(Integer year) {
    Integer y = year == null ? Date.today().year() : year;
    List<HolidayLine> lines = new List<HolidayLine>{
      line('Republic Day', Date.newInstance(y, 1, 26), null, false),
      line('May Day', Date.newInstance(y, 5, 1), null, false),
      line('Independence Day', Date.newInstance(y, 8, 15), null, false),
      line('Gandhi Jayanti', Date.newInstance(y, 10, 2), null, false),
      line('Kannada Rajyotsava', Date.newInstance(y, 11, 1), null, false),
      line('Christmas', Date.newInstance(y, 12, 25), null, false)
    };
    Map<Integer, List<Object[]>> festivals = new Map<Integer, List<Object[]>>{
      2026 => new List<Object[]>{
        new List<Object>{
          'Makara Sankranti',
          Date.newInstance(2026, 1, 14),
          null
        },
        new List<Object>{ 'Ugadi', Date.newInstance(2026, 3, 19), null },
        new List<Object>{ 'Good Friday', Date.newInstance(2026, 4, 3), null },
        new List<Object>{
          'Ganesh Chaturthi',
          Date.newInstance(2026, 9, 14),
          null
        },
        new List<Object>{
          'Dussehra break',
          Date.newInstance(2026, 10, 19),
          Date.newInstance(2026, 10, 21)
        },
        new List<Object>{
          'Deepavali break',
          Date.newInstance(2026, 11, 7),
          Date.newInstance(2026, 11, 10)
        }
      },
      2027 => new List<Object[]>{
        new List<Object>{
          'Makara Sankranti',
          Date.newInstance(2027, 1, 14),
          null
        },
        new List<Object>{ 'Good Friday', Date.newInstance(2027, 3, 26), null },
        new List<Object>{ 'Ugadi', Date.newInstance(2027, 4, 7), null },
        new List<Object>{
          'Ganesh Chaturthi',
          Date.newInstance(2027, 9, 4),
          null
        },
        new List<Object>{
          'Dussehra break',
          Date.newInstance(2027, 10, 8),
          Date.newInstance(2027, 10, 10)
        },
        new List<Object>{
          'Deepavali break',
          Date.newInstance(2027, 10, 28),
          Date.newInstance(2027, 10, 30)
        }
      }
    };
    for (
      Object[] f : festivals.containsKey(y)
        ? festivals.get(y)
        : new List<Object[]>()
    ) {
      HolidayLine h = line((String) f[0], (Date) f[1], (Date) f[2], true);
      if (f[2] != null) {
        h.closureType = 'Term Break';
      }
      lines.add(h);
    }
    lines.add(
      line(
        'Christmas and New Year break',
        Date.newInstance(y, 12, 24),
        Date.newInstance(y + 1, 1, 1),
        false
      )
    );
    lines[lines.size() - 1].closureType = 'Term Break';
    // In date order for the screen.
    List<HolidayLine> sorted = new List<HolidayLine>();
    while (!lines.isEmpty()) {
      Integer first = 0;
      for (Integer i = 1; i < lines.size(); i++) {
        if (lines[i].startDate < lines[first].startDate) {
          first = i;
        }
      }
      sorted.add(lines.remove(first));
    }
    return sorted;
  }

  private static HolidayLine line(
    String name,
    Date startDate,
    Date endDate,
    Boolean checkDate
  ) {
    HolidayLine h = new HolidayLine();
    h.name = name;
    h.startDate = startDate;
    h.endDate = endDate == null ? startDate : endDate;
    h.closureType = 'Public Holiday';
    h.checkDate = checkDate;
    return h;
  }

  // ----------------------------------------------------------------- branch

  public class BranchRequest {
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String code { get; set; }
    @AuraEnabled
    public String invoicePrefix { get; set; }
    @AuraEnabled
    public Id managerUserId { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String street { get; set; }
    @AuraEnabled
    public String city { get; set; }
    @AuraEnabled
    public String state { get; set; }
    @AuraEnabled
    public String postalCode { get; set; }
    @AuraEnabled
    public String country { get; set; }
    @AuraEnabled
    public String operatingHours { get; set; }
    @AuraEnabled
    public List<String> deliveryModes { get; set; }
    @AuraEnabled
    public Decimal taxRate { get; set; }
    @AuraEnabled
    public Integer invoiceDueDays { get; set; }
    @AuraEnabled
    public Decimal attendanceThreshold { get; set; }
    @AuraEnabled
    public Integer cancellationHours { get; set; }
    @AuraEnabled
    public List<RoomLine> rooms { get; set; }
    @AuraEnabled
    public List<HolidayLine> holidays { get; set; }
  }

  public class BranchResult {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public Integer rooms = 0;
    @AuraEnabled
    public Integer holidays = 0;
  }

  /** Opens a branch with its policies, rooms and holidays (all or nothing). */
  public static BranchResult createBranch(BranchRequest r) {
    if (!Schema.SObjectType.Branch__c.isCreateable()) {
      throw new AppException('You do not have access to open branches.');
    }
    if (r == null || String.isBlank(r.name)) {
      throw new AppException('Enter the branch name.');
    }
    if (String.isBlank(r.code)) {
      throw new AppException('Enter a branch code, for example JPN-01.');
    }
    if (String.isBlank(r.invoicePrefix)) {
      throw new AppException(
        'Enter an invoice prefix so the branch has its own invoice numbers.'
      );
    }
    String name = r.name.trim();
    String code = r.code.trim().toUpperCase();
    String prefix = r.invoicePrefix.trim().toUpperCase();
    for (Branch__c existing : [
      SELECT Name, Branch_Code__c, Invoice_Prefix__c
      FROM Branch__c
      WHERE
        Branch_Code__c = :code
        OR Invoice_Prefix__c = :prefix
        OR Name = :name
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      throw new AppException(
        existing.Branch_Code__c == code
          ? 'Branch code ' + code + ' is already used by ' + existing.Name + '.'
          : existing.Invoice_Prefix__c == prefix
              ? 'Invoice prefix ' +
                prefix +
                ' is already used by ' +
                existing.Name +
                '.'
              : 'A branch called ' + name + ' already exists.'
      );
    }
    if (r.taxRate != null && (r.taxRate < 0 || r.taxRate > 100)) {
      throw new AppException('The tax rate is a percentage from 0 to 100.');
    }
    if (
      r.attendanceThreshold != null &&
      (r.attendanceThreshold < 0 ||
      r.attendanceThreshold > 100)
    ) {
      throw new AppException(
        'The attendance minimum is a percentage from 0 to 100.'
      );
    }
    Savepoint sp = Database.setSavepoint();
    try {
      Branch__c b = new Branch__c(
        Name = name.left(80),
        Branch_Code__c = code,
        Invoice_Prefix__c = prefix,
        Active__c = true,
        Branch_Manager__c = r.managerUserId,
        Phone__c = blankToNull(r.phone),
        Email__c = blankToNull(r.email),
        Street__c = blankToNull(r.street),
        City__c = blankToNull(r.city),
        State__c = blankToNull(r.state),
        Postal_Code__c = blankToNull(r.postalCode),
        Country__c = String.isBlank(r.country) ? 'India' : r.country.trim(),
        Operating_Hours__c = blankToNull(r.operatingHours),
        Delivery_Modes__c = r.deliveryModes == null || r.deliveryModes.isEmpty()
          ? 'Classroom'
          : String.join(r.deliveryModes, ';'),
        Tax_Rate__c = r.taxRate == null ? 18 : r.taxRate,
        Invoice_Due_Days__c = r.invoiceDueDays == null ? 10 : r.invoiceDueDays,
        Attendance_Threshold__c = r.attendanceThreshold == null
          ? 75
          : r.attendanceThreshold,
        Cancellation_Notice_Hours__c = r.cancellationHours
      );
      Database.insert(b, AccessLevel.USER_MODE);
      BranchResult result = new BranchResult();
      result.branchId = b.Id;
      if (r.rooms != null && hasNamed(r.rooms)) {
        List<Room__c> rooms = buildRooms(b.Id, r.rooms);
        Database.insert(rooms, AccessLevel.USER_MODE);
        result.rooms = rooms.size();
      }
      if (r.holidays != null && !r.holidays.isEmpty()) {
        List<Calendar_Closure__c> holidays = buildHolidays(
          new Set<Id>{ b.Id },
          r.holidays,
          new HolidayResult()
        );
        Database.insert(holidays, AccessLevel.USER_MODE);
        result.holidays = holidays.size();
      }
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  private static Boolean hasNamed(List<RoomLine> lines) {
    for (RoomLine l : lines) {
      if (String.isNotBlank(l.name)) {
        return true;
      }
    }
    return false;
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }

  // ---------------------------------------------------------------- choices

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

  public class Choices {
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> managers = new List<Option>();
    @AuraEnabled
    public Boolean canCreateBranch;
    @AuraEnabled
    public Boolean canAddRooms;
    @AuraEnabled
    public Boolean canAddHolidays;
    @AuraEnabled
    public Integer year;
    @AuraEnabled
    public List<HolidayLine> suggestedHolidays;
  }

  /** Branches the user can see; possible managers (staff with a manager or administrator persona). */
  public static Choices choices() {
    Choices c = new Choices();
    for (Branch__c b : [
      SELECT Id, Name
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      c.branches.add(new Option(b.Name, b.Id));
    }
    c.canCreateBranch = Schema.SObjectType.Branch__c.isCreateable();
    c.canAddRooms = Schema.SObjectType.Room__c.isCreateable();
    c.canAddHolidays = Schema.SObjectType.Calendar_Closure__c.isCreateable();
    if (c.canCreateBranch) {
      Set<Id> seen = new Set<Id>();
      for (PermissionSetAssignment a : [
        SELECT AssigneeId, Assignee.Name
        FROM PermissionSetAssignment
        WHERE
          Assignee.IsActive = TRUE
          AND PermissionSetGroup.DeveloperName IN (
            'KEM_Branch_Manager_Persona',
            'KEM_Administrator_Persona'
          )
        WITH SYSTEM_MODE
        ORDER BY Assignee.Name
      ]) {
        if (seen.add(a.AssigneeId)) {
          c.managers.add(new Option(a.Assignee.Name, a.AssigneeId));
        }
      }
    }
    c.year = Date.today().year();
    c.suggestedHolidays = suggestedHolidays(c.year);
    return c;
  }
}
