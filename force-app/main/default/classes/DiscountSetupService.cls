/**
 * Discounts (Phase 5 stage 5): the list with how each code is used, and a
 * form to create or change one. Saves in user mode (administrators and
 * finance); usage is counted from enrolments.
 */
public with sharing class DiscountSetupService {
  public class DiscountRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String discountType;
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public String feeType;
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Id courseId;
    @AuraEnabled
    public String course;
    @AuraEnabled
    public Date validFrom;
    @AuraEnabled
    public Date validTo;
    @AuraEnabled
    public Integer maxUses;
    @AuraEnabled
    public Integer timesUsed = 0;
    @AuraEnabled
    public Boolean requiresApproval;
    @AuraEnabled
    public Boolean active;
    /** Active, Scheduled, Expired, Used up or Inactive. */
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer enrolments = 0;
    @AuraEnabled
    public Decimal amountGiven = 0;
    @AuraEnabled
    public Integer pendingApprovals = 0;
  }

  public class Overview {
    @AuraEnabled
    public List<DiscountRow> discounts = new List<DiscountRow>();
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> courses = new List<Option>();
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

  public static Overview overview() {
    if (!Schema.SObjectType.Discount__c.isAccessible()) {
      throw new AppException('You do not have access to discounts.');
    }
    Overview o = new Overview();
    o.canEdit =
      Schema.SObjectType.Discount__c.isCreateable() &&
      Schema.SObjectType.Discount__c.isUpdateable();
    Map<Id, DiscountRow> rows = new Map<Id, DiscountRow>();
    Date today = Date.today();
    for (Discount__c d : [
      SELECT
        Id,
        Code__c,
        Description__c,
        Discount_Type__c,
        Value__c,
        Fee_Type__c,
        Applies_To_Branch__c,
        Applies_To_Branch__r.Name,
        Applies_To_Course__c,
        Applies_To_Course__r.Name,
        Valid_From__c,
        Valid_To__c,
        Max_Uses__c,
        Times_Used__c,
        Requires_Approval__c,
        Active__c
      FROM Discount__c
      WITH USER_MODE
      ORDER BY Active__c DESC, Code__c
      LIMIT 500
    ]) {
      DiscountRow r = new DiscountRow();
      r.id = d.Id;
      r.code = d.Code__c;
      r.description = d.Description__c;
      r.discountType = d.Discount_Type__c;
      r.value = d.Value__c;
      r.feeType = d.Fee_Type__c;
      r.branchId = d.Applies_To_Branch__c;
      r.branch = d.Applies_To_Branch__r?.Name;
      r.courseId = d.Applies_To_Course__c;
      r.course = d.Applies_To_Course__r?.Name;
      r.validFrom = d.Valid_From__c;
      r.validTo = d.Valid_To__c;
      r.maxUses = d.Max_Uses__c == null ? null : d.Max_Uses__c.intValue();
      r.timesUsed = d.Times_Used__c == null ? 0 : d.Times_Used__c.intValue();
      r.requiresApproval = d.Requires_Approval__c;
      r.active = d.Active__c;
      r.status = status(d, today);
      rows.put(d.Id, r);
    }
    if (
      !rows.isEmpty() &&
      Schema.SObjectType.CourseOfferingParticipant.isAccessible()
    ) {
      for (AggregateResult a : [
        SELECT Discount__c d, COUNT(Id) n, SUM(Agreed_Discount__c) amount
        FROM CourseOfferingParticipant
        WHERE Discount__c IN :rows.keySet()
        WITH SYSTEM_MODE
        GROUP BY Discount__c
      ]) {
        DiscountRow r = rows.get((Id) a.get('d'));
        r.enrolments = (Integer) a.get('n');
        r.amountGiven = a.get('amount') == null ? 0 : (Decimal) a.get('amount');
      }
      for (AggregateResult a : [
        SELECT Discount__c d, COUNT(Id) n
        FROM CourseOfferingParticipant
        WHERE
          Discount__c IN :rows.keySet()
          AND Discount_Approval_Status__c = 'Pending'
        WITH SYSTEM_MODE
        GROUP BY Discount__c
      ]) {
        rows.get((Id) a.get('d')).pendingApprovals = (Integer) a.get('n');
      }
    }
    o.discounts = rows.values();
    for (Branch__c b : [
      SELECT Id, Name
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      o.branches.add(new Option(b.Name, b.Id));
    }
    if (Schema.SObjectType.LearningCourse.isAccessible()) {
      for (LearningCourse c : [
        SELECT Id, Name
        FROM LearningCourse
        WHERE IsActive = TRUE
        WITH USER_MODE
        ORDER BY Name
        LIMIT 500
      ]) {
        o.courses.add(new Option(c.Name, c.Id));
      }
    }
    return o;
  }

  @TestVisible
  private static String status(Discount__c d, Date today) {
    if (!d.Active__c) {
      return 'Inactive';
    }
    if (d.Valid_To__c != null && d.Valid_To__c < today) {
      return 'Expired';
    }
    if (d.Valid_From__c != null && d.Valid_From__c > today) {
      return 'Scheduled';
    }
    if (
      d.Max_Uses__c != null &&
      d.Times_Used__c != null &&
      d.Times_Used__c >= d.Max_Uses__c
    ) {
      return 'Used up';
    }
    return 'Active';
  }

  public class DiscountRequest {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String code { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public String discountType { get; set; }
    @AuraEnabled
    public Decimal value { get; set; }
    @AuraEnabled
    public String feeType { get; set; }
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public Id courseId { get; set; }
    @AuraEnabled
    public Date validFrom { get; set; }
    @AuraEnabled
    public Date validTo { get; set; }
    @AuraEnabled
    public Integer maxUses { get; set; }
    @AuraEnabled
    public Boolean requiresApproval { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
  }

  /** Creates or changes a discount. Codes are unique (case-insensitive). */
  public static Id save(DiscountRequest r) {
    if (
      r == null ||
      !(r.id == null
        ? Schema.SObjectType.Discount__c.isCreateable()
        : Schema.SObjectType.Discount__c.isUpdateable())
    ) {
      throw new AppException('You do not have access to change discounts.');
    }
    String code = r.code == null
      ? ''
      : r.code.trim().toUpperCase().replaceAll('\\s+', '');
    if (String.isBlank(code)) {
      throw new AppException(
        'Enter the code families or staff will use, for example SIBLING10.'
      );
    }
    if (!Pattern.matches('[A-Z0-9_-]{3,30}', code)) {
      throw new AppException('A code has 3–30 letters, numbers, - or _.');
    }
    Id selfId = r.id;
    if (
      [
        SELECT COUNT()
        FROM Discount__c
        WHERE Code__c = :code AND Id != :selfId
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException('The code ' + code + ' is already used.');
    }
    if (r.discountType != 'Percentage' && r.discountType != 'Fixed Amount') {
      throw new AppException('Choose a percentage or a fixed amount.');
    }
    if (r.value == null || r.value <= 0) {
      throw new AppException('The discount must be more than zero.');
    }
    if (r.discountType == 'Percentage' && r.value > 100) {
      throw new AppException('A percentage discount cannot exceed 100%.');
    }
    if (r.validFrom != null && r.validTo != null && r.validTo < r.validFrom) {
      throw new AppException('The last day cannot be before the first.');
    }
    if (r.maxUses != null && r.maxUses < 1) {
      throw new AppException(
        'Leave "Uses allowed" empty for no limit, or enter 1 or more.'
      );
    }
    Discount__c d = new Discount__c(
      Id = r.id,
      Code__c = code,
      Description__c = String.isBlank(r.description)
        ? null
        : r.description.trim().left(255),
      Discount_Type__c = r.discountType,
      Value__c = r.value,
      Fee_Type__c = String.isBlank(r.feeType) ? null : r.feeType,
      Applies_To_Branch__c = r.branchId,
      Applies_To_Course__c = r.courseId,
      Valid_From__c = r.validFrom,
      Valid_To__c = r.validTo,
      Max_Uses__c = r.maxUses,
      Requires_Approval__c = r.requiresApproval == true,
      Active__c = r.active != false
    );
    if (r.id == null) {
      Database.insert(d, AccessLevel.USER_MODE);
    } else {
      Database.update(d, AccessLevel.USER_MODE);
    }
    return d.Id;
  }

  /** Switches a code on or off; used codes are kept for their history. */
  public static void setActive(Id discountId, Boolean active) {
    if (!Schema.SObjectType.Discount__c.isUpdateable()) {
      throw new AppException('You do not have access to change discounts.');
    }
    Database.update(
      new Discount__c(Id = discountId, Active__c = active == true),
      AccessLevel.USER_MODE
    );
  }
}
