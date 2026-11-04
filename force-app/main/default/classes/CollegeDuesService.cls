/**
 * Finance Desk "College dues": billed, paid (allocated), due and DD/cheques
 * awaiting clearance per campus, programme, branch and academic year, plus
 * provisional admissions close to expiry and fee holds. Runs in user mode, so
 * each persona sees only the invoices and enrolments shared with them.
 */
public with sharing class CollegeDuesService {
  public static final Integer EXPIRY_WINDOW_DAYS = 3;

  public class DuesRow {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String campus;
    @AuraEnabled
    public String programme;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String academicYear;
    @AuraEnabled
    public Decimal billed = 0;
    @AuraEnabled
    public Decimal paid = 0;
    @AuraEnabled
    public Decimal due = 0;
    @AuraEnabled
    public Decimal awaitingClearance = 0;
    @AuraEnabled
    public Integer expiringSoon = 0;
    @AuraEnabled
    public Integer feeHolds = 0;
  }

  public class Dues {
    @AuraEnabled
    public List<DuesRow> rows = new List<DuesRow>();
    @AuraEnabled
    public DuesRow total = new DuesRow();
  }

  public static Dues dues() {
    Map<String, DuesRow> rows = new Map<String, DuesRow>();
    for (AggregateResult r : [
      SELECT
        Programme_Enrolment__r.Campus__r.Name campus,
        Programme_Enrolment__r.Programme__r.Name programme,
        Programme_Enrolment__r.Branch__r.Name branch,
        Programme_Enrolment__r.Academic_Year__c academicYear,
        SUM(Total__c) billed,
        SUM(Amount_Paid__c) paid,
        SUM(Balance_Due__c) due
      FROM Student_Invoice__c
      WHERE
        Programme_Enrolment__c != NULL
        AND Status__c != 'Cancelled'
        AND Status__c != 'Draft'
      WITH USER_MODE
      GROUP BY
        Programme_Enrolment__r.Campus__r.Name,
        Programme_Enrolment__r.Programme__r.Name,
        Programme_Enrolment__r.Branch__r.Name,
        Programme_Enrolment__r.Academic_Year__c
    ]) {
      DuesRow row = rowFor(rows, r);
      row.billed = nvl((Decimal) r.get('billed'));
      row.paid = nvl((Decimal) r.get('paid'));
      row.due = nvl((Decimal) r.get('due'));
    }
    for (AggregateResult r : [
      SELECT
        Student_Invoice__r.Programme_Enrolment__r.Campus__r.Name campus,
        Student_Invoice__r.Programme_Enrolment__r.Programme__r.Name programme,
        Student_Invoice__r.Programme_Enrolment__r.Branch__r.Name branch,
        Student_Invoice__r.Programme_Enrolment__r.Academic_Year__c academicYear,
        SUM(Amount__c) pending
      FROM Student_Payment__c
      WHERE
        Student_Invoice__r.Programme_Enrolment__c != NULL
        AND Status__c = 'Pending'
        AND Method__c IN :CollegeProvisionalService.INSTRUMENT_METHODS
      WITH USER_MODE
      GROUP BY
        Student_Invoice__r.Programme_Enrolment__r.Campus__r.Name,
        Student_Invoice__r.Programme_Enrolment__r.Programme__r.Name,
        Student_Invoice__r.Programme_Enrolment__r.Branch__r.Name,
        Student_Invoice__r.Programme_Enrolment__r.Academic_Year__c
    ]) {
      rowFor(rows, r).awaitingClearance = nvl((Decimal) r.get('pending'));
    }
    Date horizon = Date.today().addDays(EXPIRY_WINDOW_DAYS);
    for (Programme_Enrolment__c e : [
      SELECT
        Status__c,
        Payment_Due_By__c,
        Fee_Hold__c,
        Campus__r.Name,
        Programme__r.Name,
        Branch__r.Name,
        Academic_Year__c
      FROM Programme_Enrolment__c
      WHERE
        (Status__c = 'Provisional'
        AND Payment_Due_By__c <= :horizon)
        OR Fee_Hold__c = TRUE
      WITH USER_MODE
      LIMIT 2000
    ]) {
      DuesRow row = rowFor(
        rows,
        e.Campus__r.Name,
        e.Programme__r.Name,
        e.Branch__r.Name,
        e.Academic_Year__c
      );
      if (
        e.Status__c == 'Provisional' &&
        e.Payment_Due_By__c != null &&
        e.Payment_Due_By__c <= horizon
      ) {
        row.expiringSoon++;
      }
      if (e.Fee_Hold__c == true) {
        row.feeHolds++;
      }
    }
    Dues result = new Dues();
    List<String> keys = new List<String>(rows.keySet());
    keys.sort();
    result.total.key = 'total';
    result.total.campus = 'All colleges';
    for (String key : keys) {
      DuesRow row = rows.get(key);
      result.rows.add(row);
      result.total.billed += row.billed;
      result.total.paid += row.paid;
      result.total.due += row.due;
      result.total.awaitingClearance += row.awaitingClearance;
      result.total.expiringSoon += row.expiringSoon;
      result.total.feeHolds += row.feeHolds;
    }
    return result;
  }

  private static DuesRow rowFor(Map<String, DuesRow> rows, AggregateResult r) {
    return rowFor(
      rows,
      (String) r.get('campus'),
      (String) r.get('programme'),
      (String) r.get('branch'),
      (String) r.get('academicYear')
    );
  }

  private static DuesRow rowFor(
    Map<String, DuesRow> rows,
    String campus,
    String programme,
    String branch,
    String year
  ) {
    String key = campus + '|' + programme + '|' + branch + '|' + year;
    DuesRow row = rows.get(key);
    if (row == null) {
      row = new DuesRow();
      row.key = key;
      row.campus = campus;
      row.programme = programme;
      row.branch = branch;
      row.academicYear = year;
      rows.put(key, row);
    }
    return row;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
