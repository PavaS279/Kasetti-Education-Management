/**
 * Fees by quota for College Admission Setup.
 *
 * Prices are kept per college branch (all campuses), academic year and year of
 * study, with one column per quota; the default column (no quota) is used for
 * CET and for any quota without its own price. A change never edits a price:
 * the current price ends the day before the new one starts, so invoices already
 * issued keep their amounts and later invoices (including year-2 billing) use
 * the price that applies on their billing date.
 */
public with sharing class CollegeFeeSetupService {
  private static final List<String> DEFAULT_ROWS = new List<String>{
    'Tuition|Annual',
    'Admission|One-time'
  };

  public class Cell {
    @AuraEnabled
    public Id quotaId { get; set; }
    @AuraEnabled
    public Decimal amount { get; set; }
    /** The price used when this cell is blank (default column, or all years). */
    @AuraEnabled
    public Decimal fallback { get; set; }
  }

  public class FeeRow {
    @AuraEnabled
    public String feeType { get; set; }
    @AuraEnabled
    public String frequency { get; set; }
    @AuraEnabled
    public List<Cell> cells { get; set; }
  }

  public class QuotaColumn {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
  }

  public class FeeGrid {
    @AuraEnabled
    public List<QuotaColumn> quotas = new List<QuotaColumn>();
    @AuraEnabled
    public List<FeeRow> rows = new List<FeeRow>();
  }

  public class FeeSave {
    @AuraEnabled
    public Id courseId { get; set; }
    @AuraEnabled
    public String academicYear { get; set; }
    @AuraEnabled
    public Integer yearOfStudy { get; set; }
    @AuraEnabled
    public Date effectiveFrom { get; set; }
    @AuraEnabled
    public List<FeeRow> rows { get; set; }
  }

  private static String scopeKey(Fee_Price__c p) {
    return p.Fee_Type__c +
      '|' +
      p.Billing_Frequency__c +
      '|' +
      p.Admission_Quota__c;
  }

  /** Current all-campus prices of one branch, academic year and year of study (null: all years). */
  private static List<Fee_Price__c> current(
    Id courseId,
    String academicYear,
    Integer yearOfStudy,
    Boolean exactYear
  ) {
    String yearFilter = exactYear
      ? (yearOfStudy == null
          ? ' AND Year_Of_Study__c = NULL'
          : ' AND Year_Of_Study__c = :yearOfStudy')
      : ' AND Year_Of_Study__c = NULL';
    return Database.queryWithBinds(
      'SELECT Id, Fee_Type__c, Billing_Frequency__c, Amount__c, Admission_Quota__c, Effective_From__c ' +
        'FROM Fee_Price__c WHERE Learning_Course__c = :courseId AND Academic_Year__c = :academicYear ' +
        'AND Branch__c = NULL AND Active__c = TRUE ' +
        'AND (Effective_From__c = NULL OR Effective_From__c <= TODAY) ' +
        'AND (Effective_To__c = NULL OR Effective_To__c >= TODAY)' +
        yearFilter +
        ' ORDER BY Effective_From__c DESC NULLS LAST',
      new Map<String, Object>{
        'courseId' => courseId,
        'academicYear' => academicYear,
        'yearOfStudy' => yearOfStudy
      },
      AccessLevel.SYSTEM_MODE
    );
  }

  private static Map<String, Fee_Price__c> byScope(List<Fee_Price__c> prices) {
    Map<String, Fee_Price__c> result = new Map<String, Fee_Price__c>();
    for (Fee_Price__c p : prices) {
      if (!result.containsKey(scopeKey(p))) {
        result.put(scopeKey(p), p); // newest first
      }
    }
    return result;
  }

  public static FeeGrid grid(
    Id courseId,
    String academicYear,
    Integer yearOfStudy
  ) {
    FeeGrid g = new FeeGrid();
    QuotaColumn standard = new QuotaColumn();
    standard.name = 'Default (CET)';
    g.quotas.add(standard);
    for (Admission_Quota__c q : [
      SELECT Id, Name, Code__c
      FROM Admission_Quota__c
      WHERE Active__c = TRUE AND Code__c != :CollegeQuotaService.DEFAULT_CODE
      WITH SYSTEM_MODE
      ORDER BY Sort_Order__c NULLS LAST, Name
    ]) {
      QuotaColumn c = new QuotaColumn();
      c.id = q.Id;
      c.name = q.Name;
      g.quotas.add(c);
    }
    Map<String, Fee_Price__c> exact = byScope(
      current(courseId, academicYear, yearOfStudy, true)
    );
    Map<String, Fee_Price__c> allYears = yearOfStudy == null
      ? new Map<String, Fee_Price__c>()
      : byScope(current(courseId, academicYear, null, true));
    List<String> rowKeys = new List<String>(DEFAULT_ROWS);
    for (
      Map<String, Fee_Price__c> source : new List<Map<String, Fee_Price__c>>{
        exact,
        allYears
      }
    ) {
      for (Fee_Price__c p : source.values()) {
        String rowKey = p.Fee_Type__c + '|' + p.Billing_Frequency__c;
        if (!rowKeys.contains(rowKey)) {
          rowKeys.add(rowKey);
        }
      }
    }
    for (String rowKey : rowKeys) {
      FeeRow row = new FeeRow();
      row.feeType = rowKey.substringBefore('|');
      row.frequency = rowKey.substringAfter('|');
      row.cells = new List<Cell>();
      Decimal standardAmount;
      for (QuotaColumn col : g.quotas) {
        String key = rowKey + '|' + col.id;
        Cell cell = new Cell();
        cell.quotaId = col.id;
        cell.amount = exact.containsKey(key) ? exact.get(key).Amount__c : null;
        // Blank: the all-years price of the same column, else the default column.
        Decimal yearFallback = allYears.containsKey(key)
          ? allYears.get(key).Amount__c
          : null;
        cell.fallback = yearFallback != null
          ? yearFallback
          : (col.id == null ? null : standardAmount);
        if (col.id == null) {
          standardAmount = cell.amount != null ? cell.amount : cell.fallback;
        }
        row.cells.add(cell);
      }
      g.rows.add(row);
    }
    return g;
  }

  public static void save(FeeSave request) {
    if (
      request == null ||
      request.courseId == null ||
      String.isBlank(request.academicYear)
    ) {
      throw new AppException('Choose the branch and academic year.');
    }
    if (!Pattern.matches('^\\d{4}-\\d{2}$', request.academicYear)) {
      throw new AppException('The academic year looks like 2026-27.');
    }
    if (
      request.yearOfStudy != null &&
      (request.yearOfStudy < 1 ||
      request.yearOfStudy > 6)
    ) {
      throw new AppException('Choose a year of study from 1 to 6.');
    }
    Date startsOn = request.effectiveFrom == null
      ? Date.today()
      : request.effectiveFrom;
    if (startsOn < Date.today()) {
      throw new AppException(
        'New fees start today or later; past invoices keep their amounts.'
      );
    }
    Map<String, Fee_Price__c> existing = byScope(
      current(request.courseId, request.academicYear, request.yearOfStudy, true)
    );
    List<Fee_Price__c> ending = new List<Fee_Price__c>();
    List<Fee_Price__c> updates = new List<Fee_Price__c>();
    List<Fee_Price__c> inserts = new List<Fee_Price__c>();
    for (
      FeeRow row : request.rows == null ? new List<FeeRow>() : request.rows
    ) {
      for (Cell cell : row.cells == null ? new List<Cell>() : row.cells) {
        if (
          cell.amount != null &&
          (cell.amount < 0 ||
          cell.amount != cell.amount.setScale(2, System.RoundingMode.DOWN))
        ) {
          throw new AppException(
            'Fees are amounts of 0 or more with at most two decimals.'
          );
        }
        String key = row.feeType + '|' + row.frequency + '|' + cell.quotaId;
        Fee_Price__c old = existing.get(key);
        Decimal oldAmount = old?.Amount__c;
        if (oldAmount == cell.amount) {
          continue;
        }
        if (old != null) {
          if (
            old.Effective_From__c != null &&
            old.Effective_From__c >= startsOn
          ) {
            // Not yet started: change it in place (or stop it) instead of a zero-day price.
            if (cell.amount == null) {
              updates.add(new Fee_Price__c(Id = old.Id, Active__c = false));
            } else {
              updates.add(
                new Fee_Price__c(Id = old.Id, Amount__c = cell.amount)
              );
            }
            continue;
          }
          ending.add(
            new Fee_Price__c(
              Id = old.Id,
              Effective_To__c = startsOn.addDays(-1)
            )
          );
        }
        if (cell.amount != null) {
          inserts.add(
            new Fee_Price__c(
              Learning_Course__c = request.courseId,
              Academic_Year__c = request.academicYear,
              Year_Of_Study__c = request.yearOfStudy,
              Fee_Type__c = row.feeType,
              Billing_Frequency__c = row.frequency,
              Admission_Quota__c = cell.quotaId,
              Amount__c = cell.amount,
              Effective_From__c = startsOn,
              Active__c = true
            )
          );
        }
      }
    }
    Database.update(ending, AccessLevel.SYSTEM_MODE);
    Database.update(updates, AccessLevel.SYSTEM_MODE);
    Database.insert(inserts, AccessLevel.SYSTEM_MODE);
  }
}
