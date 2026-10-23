public without sharing class AdmissionEligibilityService {
  private static final Map<String, Integer> LEVELS = new Map<String, Integer>{
    'SSLC' => 1,
    'PUC' => 2,
    'Diploma' => 3,
    'BE' => 4
  };

  public static void evaluate(Id applicationId) {
    IndividualApplication application = [
      SELECT
        Id,
        AccountId,
        Status,
        Branch__c,
        Learning_Course__c,
        Academic_Year__c,
        Entry_Route__c,
        College_Stage__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    // College admissions track their lifecycle in College_Stage__c (ADR-005 fallback).
    if (
      isFrozen(application.Status) ||
      isCollegeFrozen(application.College_Stage__c)
    ) {
      throw new AppException(
        'Eligibility evidence is locked after the application decision.'
      );
    }
    Admission_Rule__c rule = selectRule(application);
    Evaluation result = rule == null
      ? new Evaluation(
          'Not Eligible',
          'Admissions are not open for this branch and route.'
        )
      : evaluateAgainst(application.AccountId, rule);
    Datetime evaluatedOn = System.now();
    Map<String, Object> evidence = new Map<String, Object>{
      'verdict' => result.status,
      'reason' => result.reason,
      'evaluatedAt' => evaluatedOn,
      'evaluatedBy' => UserInfo.getUserId()
    };
    if (rule != null) {
      evidence.put('ruleId', rule.Id);
      evidence.put('versionKey', rule.Version_Key__c);
      evidence.put('qualificationId', result.qualificationId);
      evidence.put('qualificationLevel', result.qualificationLevel);
      evidence.put('percentage', result.percentage);
      evidence.put('entranceScoreId', result.entranceScoreId);
      evidence.put('entranceExam', result.entranceExam);
      evidence.put('rank', result.rank);
      AdmissionRuleService.markUsed(rule.Id);
    }
    Database.update(
      new IndividualApplication(
        Id = application.Id,
        Eligibility_Status__c = result.status,
        Eligibility_Notes__c = result.reason,
        Evaluated_Rule__c = rule?.Id,
        Eligibility_Evidence__c = JSON.serialize(evidence),
        Eligibility_Evaluated_On__c = evaluatedOn
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  /**
   * Other branches at the same campus, route and year whose active rule the
   * student meets: shown to the admission desk when the chosen branch refuses.
   */
  public static List<String> suggestions(Id applicationId) {
    IndividualApplication application = [
      SELECT
        Id,
        AccountId,
        Branch__c,
        Learning_Course__c,
        Academic_Year__c,
        Entry_Route__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    Map<Id, Admission_Rule__c> byBranch = new Map<Id, Admission_Rule__c>();
    for (Admission_Rule__c rule : [
      SELECT
        Id,
        Branch__c,
        Branch__r.Name,
        Campus__c,
        Version_Key__c,
        Qualifying_Level__c,
        Qualifying_Streams__c,
        Qualifying_Branch_Codes__c,
        Min_Percentage__c,
        Entrance_Required__c,
        (
          SELECT
            Id,
            Entrance_Exam__c,
            Max_Rank__c,
            Min_Score__c,
            Exam_Year_From__c,
            Exam_Year_To__c
          FROM Accepted_Entrances__r
        )
      FROM Admission_Rule__c
      WHERE
        Academic_Year__c = :application.Academic_Year__c
        AND Entry_Route__c = :application.Entry_Route__c
        AND Status__c = 'Active'
        AND Branch__c != :application.Learning_Course__c
        AND (Campus__c = :application.Branch__c
        OR Campus__c = NULL)
      WITH SYSTEM_MODE
      ORDER BY Min_Percentage__c DESC
      LIMIT 20
    ]) {
      // A campus-specific rule wins over the all-campus rule for the same branch.
      if (!byBranch.containsKey(rule.Branch__c) || rule.Campus__c != null) {
        byBranch.put(rule.Branch__c, rule);
      }
    }
    List<String> result = new List<String>();
    for (Admission_Rule__c rule : byBranch.values()) {
      if (evaluateAgainst(application.AccountId, rule).status == 'Eligible') {
        result.add(
          rule.Branch__r.Name +
            ' (needs ' +
            rule.Min_Percentage__c.setScale(0) +
            '%)'
        );
      }
    }
    return result;
  }

  // ------------------------------------------------------------ desk preview

  public class Check {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String actual;
    @AuraEnabled
    public Boolean passed;
  }

  public class Suggestion {
    @AuraEnabled
    public Id campusBranchId;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Decimal minimum;
  }

  public class Preview {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public List<Check> checks = new List<Check>();
    @AuraEnabled
    public List<Suggestion> suggestions = new List<Suggestion>();
  }

  /** The active rule (campus-specific first) for a campus branch and entry route, with its accepted entrances. */
  public static Admission_Rule__c activeRule(Id campusBranchId, String route) {
    Campus_Branch__c intake = [
      SELECT Campus__c, Branch__c, Academic_Year__c
      FROM Campus_Branch__c
      WHERE Id = :campusBranchId
      WITH SYSTEM_MODE
    ];
    return selectRule(
      new IndividualApplication(
        Branch__c = intake.Campus__c,
        Learning_Course__c = intake.Branch__c,
        Academic_Year__c = intake.Academic_Year__c,
        Entry_Route__c = route
      )
    );
  }

  /**
   * Live check for the admission desk before anything is saved: the verdict,
   * one line per criterion and, when refused, the open branches at the same
   * campus the student meets.
   */
  public static Preview preview(
    Id campusBranchId,
    String route,
    List<Academic_Qualification__c> qualifications,
    List<Entrance_Score__c> scores
  ) {
    Preview result = new Preview();
    Admission_Rule__c rule = activeRule(campusBranchId, route);
    if (rule == null) {
      result.status = 'Not Eligible';
      result.reason = 'Admissions are not open for this branch and route.';
      return result;
    }
    List<Academic_Qualification__c> ordered = sortedBest(qualifications);
    Evaluation evaluation = evaluateWith(rule, ordered, scores);
    result.status = evaluation.status;
    result.reason = evaluation.reason;
    result.checks = checks(rule, ordered, scores);
    if (result.status == 'Not Eligible') {
      Campus_Branch__c intake = [
        SELECT Campus__c, Branch__c, Academic_Year__c, Branch__r.Programme__c
        FROM Campus_Branch__c
        WHERE Id = :campusBranchId
        WITH SYSTEM_MODE
      ];
      // Suggest other branches of the same programme (a BE applicant is offered BE branches).
      Map<Id, Campus_Branch__c> openIntakes = new Map<Id, Campus_Branch__c>();
      for (Campus_Branch__c cb : [
        SELECT Id, Branch__c
        FROM Campus_Branch__c
        WHERE
          Campus__c = :intake.Campus__c
          AND Academic_Year__c = :intake.Academic_Year__c
          AND Admissions_Open__c = TRUE
          AND Branch__c != :intake.Branch__c
          AND Branch__r.Programme__c = :intake.Branch__r.Programme__c
        WITH SYSTEM_MODE
      ]) {
        openIntakes.put(cb.Branch__c, cb);
      }
      for (
        Admission_Rule__c other : rulesFor(
          openIntakes.keySet(),
          intake.Campus__c,
          intake.Academic_Year__c,
          route
        )
      ) {
        if (evaluateWith(other, ordered, scores).status == 'Eligible') {
          Suggestion suggestion = new Suggestion();
          suggestion.campusBranchId = openIntakes.get(other.Branch__c).Id;
          suggestion.branch = other.Branch__r.Name;
          suggestion.minimum = other.Min_Percentage__c;
          result.suggestions.add(suggestion);
        }
      }
    }
    return result;
  }

  private static List<Academic_Qualification__c> sortedBest(
    List<Academic_Qualification__c> values
  ) {
    List<Academic_Qualification__c> result = new List<Academic_Qualification__c>();
    for (Academic_Qualification__c q : values) {
      if (q.Percentage__c == null) {
        continue;
      }
      Integer i = 0;
      while (i < result.size() && result[i].Percentage__c >= q.Percentage__c) {
        i++;
      }
      if (i == result.size()) {
        result.add(q);
      } else {
        result.add(i, q);
      }
    }
    return result;
  }

  private static List<Check> checks(
    Admission_Rule__c rule,
    List<Academic_Qualification__c> qualifications,
    List<Entrance_Score__c> scores
  ) {
    List<Check> result = new List<Check>();
    Academic_Qualification__c held;
    for (Academic_Qualification__c q : qualifications) {
      if (q.Level__c == rule.Qualifying_Level__c) {
        held = q;
        break;
      }
    }
    String what = rule.Qualifying_Level__c;
    if (String.isNotBlank(rule.Qualifying_Streams__c)) {
      what += ' (' + rule.Qualifying_Streams__c.replace(';', ' or ') + ')';
    }
    if (String.isNotBlank(rule.Qualifying_Branch_Codes__c)) {
      what += ' (' + rule.Qualifying_Branch_Codes__c.replace(';', ' or ') + ')';
    }
    result.add(
      check(
        what + ' at least ' + rule.Min_Percentage__c.setScale(0) + '%',
        held == null ? 'not entered' : held.Percentage__c + '%',
        held != null &&
          held.Percentage__c >= rule.Min_Percentage__c &&
          allowed(rule.Qualifying_Streams__c, held.Stream_Group__c) &&
          allowed(rule.Qualifying_Branch_Codes__c, held.Branch_Code__c)
      )
    );
    if (rule.Entrance_Required__c) {
      List<String> accepted = new List<String>();
      Boolean met = false;
      for (Admission_Rule_Entrance__c e : rule.Accepted_Entrances__r) {
        accepted.add(
          e.Entrance_Exam__c +
          (e.Max_Rank__c == null
            ? ' (any rank)'
            : ' rank up to ' + e.Max_Rank__c.format())
        );
        for (Entrance_Score__c score : scores) {
          met |= score.Exam__c == e.Entrance_Exam__c && within(score, e);
        }
      }
      String actual = scores.isEmpty()
        ? 'not entered'
        : scores[0].Exam__c +
          ' ' +
          (scores[0].Rank__c == null ? '' : scores[0].Rank__c.format());
      result.add(
        check('Entrance: ' + String.join(accepted, ' or '), actual, met)
      );
    }
    return result;
  }

  private static Check check(String label, String actual, Boolean passed) {
    Check c = new Check();
    c.label = label;
    c.actual = actual;
    c.passed = passed;
    return c;
  }

  private static List<Admission_Rule__c> rulesFor(
    Set<Id> branchIds,
    Id campusId,
    String academicYear,
    String route
  ) {
    Map<Id, Admission_Rule__c> byBranch = new Map<Id, Admission_Rule__c>();
    for (Admission_Rule__c rule : [
      SELECT
        Id,
        Branch__c,
        Branch__r.Name,
        Campus__c,
        Version_Key__c,
        Qualifying_Level__c,
        Qualifying_Streams__c,
        Qualifying_Branch_Codes__c,
        Min_Percentage__c,
        Entrance_Required__c,
        (
          SELECT
            Id,
            Entrance_Exam__c,
            Max_Rank__c,
            Min_Score__c,
            Exam_Year_From__c,
            Exam_Year_To__c
          FROM Accepted_Entrances__r
        )
      FROM Admission_Rule__c
      WHERE
        Branch__c IN :branchIds
        AND Academic_Year__c = :academicYear
        AND Entry_Route__c = :route
        AND Status__c = 'Active'
        AND (Campus__c = :campusId
        OR Campus__c = NULL)
      WITH SYSTEM_MODE
      ORDER BY Min_Percentage__c DESC
    ]) {
      if (!byBranch.containsKey(rule.Branch__c) || rule.Campus__c != null) {
        byBranch.put(rule.Branch__c, rule);
      }
    }
    return byBranch.values();
  }

  private static Admission_Rule__c selectRule(
    IndividualApplication application
  ) {
    List<Admission_Rule__c> rules = [
      SELECT
        Id,
        Campus__c,
        Version_Key__c,
        Qualifying_Level__c,
        Qualifying_Streams__c,
        Qualifying_Branch_Codes__c,
        Min_Percentage__c,
        Entrance_Required__c,
        (
          SELECT
            Id,
            Entrance_Exam__c,
            Max_Rank__c,
            Min_Score__c,
            Exam_Year_From__c,
            Exam_Year_To__c
          FROM Accepted_Entrances__r
        )
      FROM Admission_Rule__c
      WHERE
        Branch__c = :application.Learning_Course__c
        AND Academic_Year__c = :application.Academic_Year__c
        AND Entry_Route__c = :application.Entry_Route__c
        AND Status__c = 'Active'
        AND (Campus__c = :application.Branch__c
        OR Campus__c = NULL)
      WITH SYSTEM_MODE
    ];
    Admission_Rule__c fallback;
    for (Admission_Rule__c rule : rules) {
      if (rule.Campus__c == application.Branch__c)
        return rule;
      fallback = rule;
    }
    return fallback;
  }

  private static Evaluation evaluateAgainst(
    Id studentId,
    Admission_Rule__c rule
  ) {
    List<Academic_Qualification__c> qualifications = [
      SELECT Id, Level__c, Percentage__c, Stream_Group__c, Branch_Code__c
      FROM Academic_Qualification__c
      WHERE Student__c = :studentId AND Verified__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Percentage__c DESC
    ];
    List<Entrance_Score__c> scores = !rule.Entrance_Required__c
      ? new List<Entrance_Score__c>()
      : [
          SELECT Id, Exam__c, Exam_Year__c, Rank__c, Score__c
          FROM Entrance_Score__c
          WHERE Student__c = :studentId AND Verified__c = TRUE
          WITH SYSTEM_MODE
        ];
    return evaluateWith(rule, qualifications, scores);
  }

  /** The rule check on given qualifications (best first) and entrance scores; no queries. */
  private static Evaluation evaluateWith(
    Admission_Rule__c rule,
    List<Academic_Qualification__c> qualifications,
    List<Entrance_Score__c> scores
  ) {
    Academic_Qualification__c best;
    Integer requiredLevel = LEVELS.get(rule.Qualifying_Level__c);
    for (Academic_Qualification__c candidate : qualifications) {
      if (
        LEVELS.get(candidate.Level__c) != null &&
        LEVELS.get(candidate.Level__c) >= requiredLevel
      ) {
        best = candidate;
        break;
      }
    }
    if (best == null)
      return new Evaluation(
        'Not Checked',
        'Add and verify the ' + rule.Qualifying_Level__c + ' result.'
      );
    Evaluation result = new Evaluation(null, null);
    result.capture(best);
    if (!allowed(rule.Qualifying_Streams__c, best.Stream_Group__c))
      return result.fail(
        'The qualifying stream is not accepted for this branch.'
      );
    if (!allowed(rule.Qualifying_Branch_Codes__c, best.Branch_Code__c))
      return result.fail(
        'The qualifying diploma branch is not accepted for this branch.'
      );
    if (best.Percentage__c < rule.Min_Percentage__c)
      return result.fail(
        'This branch needs ' +
          rule.Min_Percentage__c +
          '%; the student has ' +
          best.Percentage__c +
          '%.'
      );
    if (rule.Entrance_Required__c) {
      if (scores.isEmpty())
        return result.notChecked('Add and verify an accepted entrance score.');
      for (Admission_Rule_Entrance__c accepted : rule.Accepted_Entrances__r) {
        for (Entrance_Score__c score : scores) {
          if (
            score.Exam__c == accepted.Entrance_Exam__c &&
            within(score, accepted)
          ) {
            result.capture(score);
            result.status = 'Eligible';
            result.reason = 'The verified qualification and entrance score meet the active rule.';
            return result;
          }
        }
      }
      return result.fail(
        'The verified entrance scores do not meet this branch rule.'
      );
    }
    result.status = 'Eligible';
    result.reason = 'The verified qualification meets the active rule.';
    return result;
  }

  private static Boolean within(
    Entrance_Score__c score,
    Admission_Rule_Entrance__c accepted
  ) {
    return (accepted.Exam_Year_From__c == null ||
      score.Exam_Year__c >= accepted.Exam_Year_From__c) &&
      (accepted.Exam_Year_To__c == null ||
      score.Exam_Year__c <= accepted.Exam_Year_To__c) &&
      (accepted.Max_Rank__c == null ||
      (score.Rank__c != null &&
      score.Rank__c <= accepted.Max_Rank__c)) &&
      (accepted.Min_Score__c == null ||
      (score.Score__c != null &&
      score.Score__c >= accepted.Min_Score__c));
  }

  private static Boolean allowed(String configured, String actual) {
    if (String.isBlank(configured))
      return true;
    if (String.isBlank(actual))
      return false;
    for (String value : configured.split('[;,]'))
      if (value.trim().equalsIgnoreCase(actual.trim()))
        return true;
    return false;
  }

  private static Boolean isFrozen(String status) {
    return new Set<String>{
        'Application Decision',
        'Enrolled',
        'Withdrawn',
        'Cancelled',
        'Canceled'
      }
      .contains(status);
  }

  /** College stages after the Dean's decision: the evidence snapshot is frozen. */
  private static Boolean isCollegeFrozen(String stage) {
    return new Set<String>{
        'Application Decision',
        'Fee Pending',
        'Enrolled',
        'Enrollment Failed',
        'Withdrawn'
      }
      .contains(stage);
  }

  private class Evaluation {
    String status;
    String reason;
    Id qualificationId;
    String qualificationLevel;
    Decimal percentage;
    Id entranceScoreId;
    String entranceExam;
    Decimal rank;
    Evaluation(String status, String reason) {
      this.status = status;
      this.reason = reason;
    }
    void capture(Academic_Qualification__c value) {
      qualificationId = value.Id;
      qualificationLevel = value.Level__c;
      percentage = value.Percentage__c;
    }
    void capture(Entrance_Score__c value) {
      entranceScoreId = value.Id;
      entranceExam = value.Exam__c;
      rank = value.Rank__c;
    }
    Evaluation fail(String message) {
      status = 'Not Eligible';
      reason = message;
      return this;
    }
    Evaluation notChecked(String message) {
      status = 'Not Checked';
      reason = message;
      return this;
    }
  }
}
