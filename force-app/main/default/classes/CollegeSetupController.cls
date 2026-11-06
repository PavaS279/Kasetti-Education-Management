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
    @AuraEnabled
    public Rule regularRule;
    @AuraEnabled
    public Rule lateralRule;
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
