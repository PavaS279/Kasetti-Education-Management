/**
 * College Admission Setup: one screen for the BE college intake settings,
 * one row per campus branch and academic year.
 *
 * Everyone with college access may view it; only System Administrators
 * (Modify All Data on the profile) may change it, and the server refuses
 * changes from anyone else. Intake changes are kept by field history on the
 * campus branch; eligibility changes create a new rule version (the active
 * rule is copied as a draft, edited, and activated), so earlier versions stay.
 */
public with sharing class CollegeSetupController {
  public class Rule {
    @AuraEnabled
    public Id ruleId;
    @AuraEnabled
    public Integer version;
    @AuraEnabled
    public String qualifyingLevel;
    @AuraEnabled
    public Decimal minPercentage;
    @AuraEnabled
    public Boolean entranceRequired = false;
    /** True when the rule has no campus: it applies at every campus. */
    @AuraEnabled
    public Boolean allCampuses = false;
    @AuraEnabled
    public List<Entrance> entrances = new List<Entrance>();
  }

  public class Entrance {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String exam;
    @AuraEnabled
    public Decimal maxRank;
  }

  public class Row {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String campus;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String academicYear;
    @AuraEnabled
    public Decimal intakeRegular;
    @AuraEnabled
    public Decimal intakeLateral;
    @AuraEnabled
    public Decimal usedRegular;
    @AuraEnabled
    public Decimal usedLateral;
    @AuraEnabled
    public Boolean admissionsOpen = false;
    @AuraEnabled
    public Boolean deanExceptionsAllowed = true;
    /** Regular seats per active quota (every active quota listed, 0 when unset). */
    @AuraEnabled
    public List<SplitEntry> split = new List<SplitEntry>();
    @AuraEnabled
    public Rule regularRule;
    @AuraEnabled
    public Rule lateralRule;
  }

  public class QuotaDef {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public String code { get; set; }
    @AuraEnabled
    public String rankExam { get; set; }
    @AuraEnabled
    public String extraDocument { get; set; }
    @AuraEnabled
    public Boolean active { get; set; }
    @AuraEnabled
    public Decimal sortOrder { get; set; }
  }

  public class SplitEntry {
    @AuraEnabled
    public Id quotaId { get; set; }
    @AuraEnabled
    public String name { get; set; }
    @AuraEnabled
    public Decimal seats { get; set; }
    @AuraEnabled
    public Integer taken { get; set; }
  }

  public class Change implements Comparable {
    @AuraEnabled
    public Datetime changedOn;
    @AuraEnabled
    public String changedBy;
    @AuraEnabled
    public String what;
    @AuraEnabled
    public String fromValue;
    @AuraEnabled
    public String toValue;

    public Integer compareTo(Object other) {
      Datetime theirs = ((Change) other).changedOn;
      if (changedOn == theirs) {
        return 0;
      }
      return changedOn == null || (theirs != null && changedOn < theirs)
        ? 1
        : -1;
    }
  }

  public class Setup {
    @AuraEnabled
    public Boolean canEdit = false;
    @AuraEnabled
    public List<Row> rows = new List<Row>();
    @AuraEnabled
    public List<Change> history = new List<Change>();
    @AuraEnabled
    public List<QuotaDef> quotas = new List<QuotaDef>();
  }

  public class IntakeChange {
    @AuraEnabled
    public Id id { get; set; }
    @AuraEnabled
    public Decimal intakeRegular { get; set; }
    @AuraEnabled
    public Decimal intakeLateral { get; set; }
    @AuraEnabled
    public Boolean admissionsOpen { get; set; }
    @AuraEnabled
    public Boolean deanExceptionsAllowed { get; set; }
  }

  public class RuleChange {
    @AuraEnabled
    public Id ruleId { get; set; }
    @AuraEnabled
    public Decimal minPercentage { get; set; }
    @AuraEnabled
    public List<Entrance> entrances { get; set; }
  }

  /** System Administrators only: Modify All Data on the profile. */
  public static Boolean canEdit() {
    return [
      SELECT PermissionsModifyAllData
      FROM Profile
      WHERE Id = :UserInfo.getProfileId()
      WITH SYSTEM_MODE
    ]
    .PermissionsModifyAllData;
  }

  private static void assertCanEdit() {
    if (!canEdit()) {
      throw new AppException(
        'Only a System Administrator can change the college admission setup.'
      );
    }
  }

  private static void assertCanView() {
    if (
      !canEdit() &&
      !FeatureManagement.checkPermission(
        CollegeDocumentService.VERIFY_PERMISSION
      ) &&
      !FeatureManagement.checkPermission(InterviewService.PERMISSION)
    ) {
      throw new AppException(
        'Only college admission staff can see the college admission setup.'
      );
    }
  }

  @AuraEnabled
  public static Setup getSetup() {
    try {
      assertCanView();
      Setup result = new Setup();
      result.canEdit = canEdit();
      Reader reader = new Reader();
      Map<String, Rule> rules = reader.rules();
      List<Admission_Quota__c> quotas = reader.quotas();
      for (Admission_Quota__c q : quotas) {
        QuotaDef d = new QuotaDef();
        d.id = q.Id;
        d.name = q.Name;
        d.code = q.Code__c;
        d.rankExam = q.Rank_Exam__c;
        d.extraDocument = q.Extra_Document__c;
        d.active = q.Active__c;
        d.sortOrder = q.Sort_Order__c;
        result.quotas.add(d);
      }
      Map<String, Decimal> seats = reader.seats();
      Map<String, Integer> taken = reader.taken(
        quotas.isEmpty() ? null : CollegeQuotaService.defaultQuota()?.Id
      );
      for (Campus_Branch__c cb : reader.intakes()) {
        Row r = new Row();
        r.id = cb.Id;
        r.campus = cb.Campus__r.Name;
        r.branch = cb.Branch__r.Name;
        r.academicYear = cb.Academic_Year__c;
        r.intakeRegular = cb.Intake_Regular__c;
        r.intakeLateral = cb.Intake_Lateral__c;
        r.usedRegular =
          nvl(cb.Reserved_Regular__c) + nvl(cb.Finalised_Regular__c);
        r.usedLateral =
          nvl(cb.Reserved_Lateral__c) + nvl(cb.Finalised_Lateral__c);
        r.admissionsOpen = cb.Admissions_Open__c;
        r.deanExceptionsAllowed = cb.Dean_Exceptions_Allowed__c;
        for (Admission_Quota__c q : quotas) {
          if (!q.Active__c) {
            continue;
          }
          String key = cb.Id + '|' + q.Id;
          SplitEntry e = new SplitEntry();
          e.quotaId = q.Id;
          e.name = q.Name;
          e.seats = seats.containsKey(key) ? seats.get(key) : 0;
          e.taken = taken.containsKey(key) ? taken.get(key) : 0;
          r.split.add(e);
        }
        r.regularRule = ruleFor(rules, cb, 'Regular');
        r.lateralRule = ruleFor(rules, cb, 'Lateral');
        result.rows.add(r);
      }
      result.history = reader.history();
      result.history.sort();
      return result;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Setup saveIntake(IntakeChange change) {
    try {
      assertCanEdit();
      if (change == null || change.id == null) {
        throw new AppException('Choose a campus branch.');
      }
      Campus_Branch__c cb = [
        SELECT
          Reserved_Regular__c,
          Finalised_Regular__c,
          Reserved_Lateral__c,
          Finalised_Lateral__c
        FROM Campus_Branch__c
        WHERE Id = :change.id
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      Decimal usedRegular =
        nvl(cb.Reserved_Regular__c) + nvl(cb.Finalised_Regular__c);
      Decimal usedLateral =
        nvl(cb.Reserved_Lateral__c) + nvl(cb.Finalised_Lateral__c);
      if (
        !wholeNumber(change.intakeRegular) || !wholeNumber(change.intakeLateral)
      ) {
        throw new AppException('Seats are whole numbers of 0 or more.');
      }
      if (
        change.intakeRegular < usedRegular ||
        change.intakeLateral < usedLateral
      ) {
        throw new AppException(
          'Seats cannot go below the seats already taken (regular ' +
            usedRegular.intValue() +
            ', lateral ' +
            usedLateral.intValue() +
            ').'
        );
      }
      Database.update(
        new Campus_Branch__c(
          Id = change.id,
          Intake_Regular__c = change.intakeRegular,
          Intake_Lateral__c = change.intakeLateral,
          Admissions_Open__c = change.admissionsOpen == true,
          Dean_Exceptions_Allowed__c = change.deanExceptionsAllowed == true
        ),
        AccessLevel.SYSTEM_MODE
      );
      return getSetup();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Adds or changes a quota in the list (CET, Management, COMEDK, SNQ, ...). */
  @AuraEnabled
  public static Setup saveQuota(QuotaDef quota) {
    try {
      assertCanEdit();
      if (
        quota == null ||
        String.isBlank(quota.name) ||
        String.isBlank(quota.code)
      ) {
        throw new AppException('Enter the quota name and a short code.');
      }
      String code = quota.code.trim().toUpperCase();
      if (!Pattern.matches('^[A-Z0-9_]{2,20}$', code)) {
        throw new AppException(
          'The code is 2 to 20 letters, digits or underscores (for example SNQ).'
        );
      }
      Database.upsert(
        new Admission_Quota__c(
          Id = quota.id,
          Name = quota.name.trim().left(80),
          Code__c = code,
          Rank_Exam__c = String.isBlank(quota.rankExam)
            ? null
            : quota.rankExam.trim().left(40),
          Extra_Document__c = String.isBlank(quota.extraDocument)
            ? null
            : quota.extraDocument.trim().left(80),
          Active__c = quota.active != false,
          Sort_Order__c = quota.sortOrder
        ),
        AccessLevel.SYSTEM_MODE
      );
      return getSetup();
    } catch (DmlException e) {
      throw AppException.toAura(
        new AppException(
          e.getDmlType(0) == StatusCode.DUPLICATE_VALUE
            ? 'Another quota already uses this code.'
            : e.getDmlMessage(0)
        )
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Regular seats per quota for one campus branch: they must add up to the regular intake. */
  @AuraEnabled
  public static Setup saveSplit(Id campusBranchId, List<SplitEntry> split) {
    try {
      assertCanEdit();
      Campus_Branch__c cb = [
        SELECT Id, Intake_Regular__c
        FROM Campus_Branch__c
        WHERE Id = :campusBranchId
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      Map<Id, Integer> taken = CollegeQuotaService.takenBy(campusBranchId);
      Map<Id, Admission_Quota__c> names = new Map<Id, Admission_Quota__c>(
        [SELECT Id, Name FROM Admission_Quota__c WITH SYSTEM_MODE]
      );
      Decimal total = 0;
      List<String> parts = new List<String>();
      List<Seat_Quota__c> rows = new List<Seat_Quota__c>();
      for (SplitEntry e : split == null ? new List<SplitEntry>() : split) {
        if (!names.containsKey(e.quotaId)) {
          throw new AppException('Unknown quota.');
        }
        if (!wholeNumber(e.seats)) {
          throw new AppException('Seats are whole numbers of 0 or more.');
        }
        String name = names.get(e.quotaId).Name;
        Integer used = taken.containsKey(e.quotaId) ? taken.get(e.quotaId) : 0;
        if (e.seats < used) {
          throw new AppException(
            name + ' cannot go below the ' + used + ' seats already taken.'
          );
        }
        total += e.seats;
        parts.add(name + ' ' + e.seats.intValue());
        rows.add(
          new Seat_Quota__c(
            Campus_Branch__c = campusBranchId,
            Admission_Quota__c = e.quotaId,
            Seats__c = e.seats,
            Unique_Key__c = campusBranchId + '|' + e.quotaId
          )
        );
      }
      Decimal intake = cb.Intake_Regular__c == null ? 0 : cb.Intake_Regular__c;
      if (total != intake) {
        throw new AppException(
          String.join(parts, ' + ') +
            ' = ' +
            total.intValue() +
            '; the regular intake is ' +
            intake.intValue() +
            '. Make them equal.'
        );
      }
      // Match existing rows by campus branch and quota (also rows made without a key).
      Map<Id, Id> existing = new Map<Id, Id>();
      for (Seat_Quota__c sq : [
        SELECT Id, Admission_Quota__c
        FROM Seat_Quota__c
        WHERE Campus_Branch__c = :campusBranchId
        WITH SYSTEM_MODE
      ]) {
        existing.put(sq.Admission_Quota__c, sq.Id);
      }
      for (Seat_Quota__c sq : rows) {
        sq.Id = existing.get(sq.Admission_Quota__c);
      }
      Database.upsert(rows, AccessLevel.SYSTEM_MODE);
      return getSetup();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** New version of the rule: copy the active one, change it, activate it. */
  @AuraEnabled
  public static Setup saveRule(RuleChange change) {
    Savepoint checkpoint = Database.setSavepoint();
    try {
      assertCanEdit();
      if (change == null || change.ruleId == null) {
        throw new AppException('Choose an eligibility rule.');
      }
      if (!InputValidator.isPercentage(change.minPercentage)) {
        throw new AppException(
          'The minimum percentage is from 0 to 100 with at most two decimals.'
        );
      }
      Map<String, Decimal> ranks = new Map<String, Decimal>();
      for (
        Entrance e : change.entrances == null
          ? new List<Entrance>()
          : change.entrances
      ) {
        if (e.maxRank != null && (!wholeNumber(e.maxRank) || e.maxRank < 1)) {
          throw new AppException(
            'The highest accepted rank for ' + e.exam + ' must be 1 or more.'
          );
        }
        ranks.put(e.exam, e.maxRank);
      }
      Id draftId = AdmissionRuleService.cloneAsDraft(change.ruleId);
      Database.update(
        new Admission_Rule__c(
          Id = draftId,
          Min_Percentage__c = change.minPercentage
        ),
        AccessLevel.SYSTEM_MODE
      );
      List<Admission_Rule_Entrance__c> entrances = new List<Admission_Rule_Entrance__c>();
      for (Admission_Rule_Entrance__c e : [
        SELECT Id, Entrance_Exam__c
        FROM Admission_Rule_Entrance__c
        WHERE Admission_Rule__c = :draftId
        WITH SYSTEM_MODE
      ]) {
        if (ranks.containsKey(e.Entrance_Exam__c)) {
          entrances.add(
            new Admission_Rule_Entrance__c(
              Id = e.Id,
              Max_Rank__c = ranks.get(e.Entrance_Exam__c)
            )
          );
        }
      }
      Database.update(entrances, AccessLevel.SYSTEM_MODE);
      AdmissionRuleService.activate(draftId);
      return getSetup();
    } catch (AppException e) {
      Database.rollback(checkpoint);
      throw AppException.toAura(e);
    } catch (Exception e) {
      // Administrators see the reason (for example a rule-validation error).
      Database.rollback(checkpoint);
      throw AppException.toAura(
        new AppException('The rule was not saved: ' + e.getMessage())
      );
    }
  }

  /** A campus-specific rule wins over the all-campus rule, as in eligibility checks. */
  private static Rule ruleFor(
    Map<String, Rule> rules,
    Campus_Branch__c cb,
    String route
  ) {
    String tail = '|' + cb.Branch__c + '|' + cb.Academic_Year__c + '|' + route;
    Rule own = rules.get(cb.Campus__c + tail);
    return own != null ? own : rules.get('ALL' + tail);
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  private static Boolean wholeNumber(Decimal value) {
    return value != null &&
      value >= 0 &&
      value == value.setScale(0, System.RoundingMode.DOWN);
  }

  /** Reads college setup for every viewer, after the access check above. */
  private without sharing class Reader {
    List<Admission_Quota__c> quotas() {
      return [
        SELECT
          Id,
          Name,
          Code__c,
          Rank_Exam__c,
          Extra_Document__c,
          Active__c,
          Sort_Order__c
        FROM Admission_Quota__c
        WITH SYSTEM_MODE
        ORDER BY Sort_Order__c NULLS LAST, Name
        LIMIT 50
      ];
    }

    /** Seats per campus branch and quota, keyed "campusBranchId|quotaId". */
    Map<String, Decimal> seats() {
      Map<String, Decimal> result = new Map<String, Decimal>();
      for (Seat_Quota__c sq : [
        SELECT Campus_Branch__c, Admission_Quota__c, Seats__c
        FROM Seat_Quota__c
        WITH SYSTEM_MODE
        LIMIT 5000
      ]) {
        result.put(
          sq.Campus_Branch__c + '|' + sq.Admission_Quota__c,
          sq.Seats__c
        );
      }
      return result;
    }

    /** Regular seats taken per campus branch and quota (no quota: the default one). */
    Map<String, Integer> taken(Id fallbackQuotaId) {
      Map<String, Integer> result = new Map<String, Integer>();
      for (AggregateResult row : [
        SELECT
          Campus_Branch__c intake,
          Admission_Quota__c quota,
          COUNT(Id) total
        FROM Seat_Reservation__c
        WHERE
          Entry_Route__c = 'Regular'
          AND Status__c IN ('Reserved', 'Finalised')
        WITH SYSTEM_MODE
        GROUP BY Campus_Branch__c, Admission_Quota__c
      ]) {
        Id quotaId = (Id) row.get('quota');
        if (quotaId == null) {
          quotaId = fallbackQuotaId;
        }
        if (quotaId == null) {
          continue;
        }
        String key = String.valueOf(row.get('intake')) + '|' + quotaId;
        result.put(
          key,
          (result.containsKey(key) ? result.get(key) : 0) +
          Integer.valueOf(row.get('total'))
        );
      }
      return result;
    }

    List<Campus_Branch__c> intakes() {
      return [
        SELECT
          Id,
          Campus__c,
          Campus__r.Name,
          Branch__c,
          Branch__r.Name,
          Academic_Year__c,
          Intake_Regular__c,
          Intake_Lateral__c,
          Reserved_Regular__c,
          Finalised_Regular__c,
          Reserved_Lateral__c,
          Finalised_Lateral__c,
          Admissions_Open__c,
          Dean_Exceptions_Allowed__c
        FROM Campus_Branch__c
        WHERE Campus__r.Institution_Type__c = 'College'
        WITH SYSTEM_MODE
        ORDER BY Campus__r.Name, Branch__r.Name, Academic_Year__c DESC
        LIMIT 500
      ];
    }

    Map<String, Rule> rules() {
      Map<String, Rule> result = new Map<String, Rule>();
      for (Admission_Rule__c r : [
        SELECT
          Id,
          Campus__c,
          Branch__c,
          Academic_Year__c,
          Entry_Route__c,
          Version__c,
          Qualifying_Level__c,
          Min_Percentage__c,
          Entrance_Required__c,
          (
            SELECT Id, Entrance_Exam__c, Max_Rank__c
            FROM Accepted_Entrances__r
            ORDER BY Entrance_Exam__c
          )
        FROM Admission_Rule__c
        WHERE
          Status__c = 'Active'
          AND Branch__r.RecordType.DeveloperName = 'College_Branch'
        WITH SYSTEM_MODE
        LIMIT 1000
      ]) {
        Rule rule = new Rule();
        rule.ruleId = r.Id;
        rule.version = r.Version__c == null ? null : r.Version__c.intValue();
        rule.qualifyingLevel = r.Qualifying_Level__c;
        rule.minPercentage = r.Min_Percentage__c;
        rule.entranceRequired = r.Entrance_Required__c;
        rule.allCampuses = r.Campus__c == null;
        for (Admission_Rule_Entrance__c e : r.Accepted_Entrances__r) {
          Entrance entrance = new Entrance();
          entrance.id = e.Id;
          entrance.exam = e.Entrance_Exam__c;
          entrance.maxRank = e.Max_Rank__c;
          rule.entrances.add(entrance);
        }
        result.put(
          (r.Campus__c == null ? 'ALL' : String.valueOf(r.Campus__c)) +
            '|' +
            r.Branch__c +
            '|' +
            r.Academic_Year__c +
            '|' +
            r.Entry_Route__c,
          rule
        );
      }
      return result;
    }

    List<Change> history() {
      List<Change> result = new List<Change>();
      Map<String, String> labels = new Map<String, String>{
        'Intake_Regular__c' => 'Regular seats',
        'Intake_Lateral__c' => 'Lateral seats',
        'Admissions_Open__c' => 'Admissions open',
        'Dean_Exceptions_Allowed__c' => 'Dean exceptions allowed'
      };
      for (Campus_Branch__History h : [
        SELECT
          CreatedDate,
          CreatedBy.Name,
          Field,
          OldValue,
          NewValue,
          Parent.Name
        FROM Campus_Branch__History
        WHERE Field IN :labels.keySet()
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
        LIMIT 30
      ]) {
        Change c = new Change();
        c.changedOn = h.CreatedDate;
        c.changedBy = h.CreatedBy.Name;
        c.what = labels.get(h.Field) + ' · ' + h.Parent.Name;
        c.fromValue = String.valueOf(h.OldValue);
        c.toValue = String.valueOf(h.NewValue);
        result.add(c);
      }
      for (Admission_Rule__c r : [
        SELECT
          Effective_From__c,
          LastModifiedBy.Name,
          Version__c,
          Min_Percentage__c,
          Entry_Route__c,
          Branch__r.Name,
          Campus__r.Name
        FROM Admission_Rule__c
        WHERE
          Branch__r.RecordType.DeveloperName = 'College_Branch'
          AND Version__c > 1
          AND Effective_From__c != NULL
        WITH SYSTEM_MODE
        ORDER BY Effective_From__c DESC
        LIMIT 30
      ]) {
        Change c = new Change();
        c.changedOn = r.Effective_From__c;
        c.changedBy = r.LastModifiedBy.Name;
        c.what =
          'Eligibility rule v' +
          r.Version__c.intValue() +
          ' (' +
          r.Entry_Route__c +
          ') · ' +
          (r.Campus__c == null ? 'All campuses' : r.Campus__r.Name) +
          ' · ' +
          r.Branch__r.Name;
        c.toValue = 'Minimum ' + r.Min_Percentage__c + '%';
        result.add(c);
      }
      return result;
    }
  }
}
