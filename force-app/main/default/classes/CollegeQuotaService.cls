/**
 * Admission quotas (CET, Management, COMEDK, SNQ, ...) for regular college entry.
 *
 * A System Administrator sets each campus branch's seats per quota in College
 * Admission Setup. Seats taken are counted from the seat reservations (reserved
 * or finalised), so released and expired seats return to their quota. A branch
 * without quota rows keeps a single regular pool. An admission without a quota
 * counts against the default quota (CET). A quota may require an entrance rank
 * (for example KCET) and may add a document to the checklist (for example an
 * income certificate for SNQ).
 */
public without sharing class CollegeQuotaService {
  public static final String DEFAULT_CODE = 'CET';
  private static final Set<String> TAKEN = new Set<String>{
    'Reserved',
    'Finalised'
  };

  public class QuotaSeats {
    @AuraEnabled
    public Id quotaId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String rankExam;
    @AuraEnabled
    public String extraDocument;
    @AuraEnabled
    public Integer seats = 0;
    @AuraEnabled
    public Integer taken = 0;
    @AuraEnabled
    public Integer available = 0;
  }

  public static Admission_Quota__c defaultQuota() {
    List<Admission_Quota__c> rows = [
      SELECT Id, Name, Code__c, Rank_Exam__c, Extra_Document__c
      FROM Admission_Quota__c
      WHERE Code__c = :DEFAULT_CODE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** Active quotas of the intake with their seats; empty when the branch has no quota split. */
  public static List<QuotaSeats> seatsFor(Id campusBranchId) {
    List<QuotaSeats> result = new List<QuotaSeats>();
    if (campusBranchId == null) {
      return result;
    }
    List<Seat_Quota__c> rows = [
      SELECT
        Seats__c,
        Admission_Quota__c,
        Admission_Quota__r.Name,
        Admission_Quota__r.Code__c,
        Admission_Quota__r.Rank_Exam__c,
        Admission_Quota__r.Extra_Document__c
      FROM Seat_Quota__c
      WHERE
        Campus_Branch__c = :campusBranchId
        AND Admission_Quota__r.Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Admission_Quota__r.Sort_Order__c, Admission_Quota__r.Name
    ];
    if (rows.isEmpty()) {
      return result; // no quota split: one query, nothing more
    }
    Map<Id, Integer> taken = takenBy(campusBranchId);
    for (Seat_Quota__c sq : rows) {
      QuotaSeats q = new QuotaSeats();
      q.quotaId = sq.Admission_Quota__c;
      q.name = sq.Admission_Quota__r.Name;
      q.code = sq.Admission_Quota__r.Code__c;
      q.rankExam = sq.Admission_Quota__r.Rank_Exam__c;
      q.extraDocument = sq.Admission_Quota__r.Extra_Document__c;
      q.seats = sq.Seats__c == null ? 0 : sq.Seats__c.intValue();
      q.taken = taken.containsKey(q.quotaId) ? taken.get(q.quotaId) : 0;
      q.available = Math.max(0, q.seats - q.taken);
      result.add(q);
    }
    return result;
  }

  /** Regular seats taken per quota; seats without a quota count against the default. */
  public static Map<Id, Integer> takenBy(Id campusBranchId) {
    Map<Id, Integer> result = new Map<Id, Integer>();
    Admission_Quota__c fallback = defaultQuota();
    for (AggregateResult row : [
      SELECT Admission_Quota__c quota, COUNT(Id) total
      FROM Seat_Reservation__c
      WHERE
        Campus_Branch__c = :campusBranchId
        AND Entry_Route__c = 'Regular'
        AND Status__c IN :TAKEN
      WITH SYSTEM_MODE
      GROUP BY Admission_Quota__c
    ]) {
      Id quotaId = (Id) row.get('quota');
      if (quotaId == null) {
        quotaId = fallback?.Id;
      }
      if (quotaId != null) {
        Integer count = Integer.valueOf(row.get('total'));
        result.put(
          quotaId,
          (result.containsKey(quotaId) ? result.get(quotaId) : 0) + count
        );
      }
    }
    return result;
  }

  /**
   * At Admit (the intake row is already locked by the caller): checks the
   * quota's seats and rank rule and returns the quota to stamp on the seat.
   * Null when the branch has no quota split (the regular pool applies).
   */
  public static Id claim(IndividualApplication admission, String branchName) {
    if (admission.Entry_Route__c != 'Regular') {
      return null;
    }
    List<QuotaSeats> quotas = seatsFor(admission.Campus_Branch__c);
    if (quotas.isEmpty()) {
      return null;
    }
    Id quotaId = admission.Admission_Quota__c;
    if (quotaId == null) {
      quotaId = defaultQuota()?.Id;
    }
    QuotaSeats chosen;
    for (QuotaSeats q : quotas) {
      if (q.quotaId == quotaId) {
        chosen = q;
      }
    }
    if (chosen == null) {
      throw new AppException(
        'This branch has no seats in the chosen quota; choose another quota.'
      );
    }
    if (chosen.available < 1) {
      throw new AppException(
        chosen.name +
          ' seats for ' +
          branchName +
          ' are full (' +
          chosen.taken +
          ' of ' +
          chosen.seats +
          ').'
      );
    }
    assertRank(admission.AccountId, chosen);
    return chosen.quotaId;
  }

  private static void assertRank(Id studentId, QuotaSeats quota) {
    if (String.isBlank(quota.rankExam)) {
      return;
    }
    Integer ranks = [
      SELECT COUNT()
      FROM Entrance_Score__c
      WHERE
        Student__c = :studentId
        AND Exam__c = :quota.rankExam
        AND Rank__c != NULL
      WITH SYSTEM_MODE
    ];
    if (ranks == 0) {
      throw new AppException(
        'The ' +
          quota.name +
          ' quota needs a ' +
          quota.rankExam +
          ' rank; add it to the student\'s entrance scores or choose another quota.'
      );
    }
  }

  /** Counsellor changes the quota before Admit; the quota's extra document joins the checklist. */
  public static void setQuota(Id applicationId, Id quotaId) {
    RecordAccess.assertPermission(CollegeDocumentService.VERIFY_PERMISSION);
    RecordAccess.assertEditable(applicationId);
    IndividualApplication a = [
      SELECT Id, College_Mode__c, College_Stage__c, Campus_Branch__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (
      !a.College_Mode__c ||
      !new Set<String>{
          'Processing',
          'In Review',
          'Documents Verified',
          InterviewService.AWAITING_DEAN
        }
        .contains(a.College_Stage__c)
    ) {
      throw new AppException('The quota can be changed only before Admit.');
    }
    Boolean offered = false;
    for (QuotaSeats q : seatsFor(a.Campus_Branch__c)) {
      offered = offered || q.quotaId == quotaId;
    }
    if (!offered) {
      throw new AppException('Choose a quota this branch has seats in.');
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        Admission_Quota__c = quotaId
      ),
      AccessLevel.SYSTEM_MODE
    );
    addExtraDocument(applicationId, quotaId);
  }

  /** Adds the quota's extra document (for example Income certificate) once. */
  public static void addExtraDocument(Id applicationId, Id quotaId) {
    if (quotaId == null) {
      return;
    }
    Admission_Quota__c quota = [
      SELECT Extra_Document__c
      FROM Admission_Quota__c
      WHERE Id = :quotaId
      WITH SYSTEM_MODE
    ];
    if (String.isBlank(quota.Extra_Document__c)) {
      return;
    }
    Integer existing = [
      SELECT COUNT()
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :applicationId AND Name = :quota.Extra_Document__c
      WITH SYSTEM_MODE
    ];
    if (existing == 0) {
      Database.insert(
        new DocumentChecklistItem(
          Name = quota.Extra_Document__c,
          ParentRecordId = applicationId,
          IsRequired = true,
          Status = 'New'
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  /** For the public form: quotas of the intake that still have seats. */
  public static List<QuotaSeats> openQuotas(Id campusBranchId) {
    List<QuotaSeats> result = new List<QuotaSeats>();
    for (QuotaSeats q : seatsFor(campusBranchId)) {
      if (q.available > 0) {
        result.add(q);
      }
    }
    return result;
  }
}
