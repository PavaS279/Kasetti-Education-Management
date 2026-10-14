public without sharing class AdmissionEligibilityService {
  private static final Map<String, Integer> LEVELS = new Map<String, Integer>{
    'SSLC' => 1,
    'PUC' => 2,
    'Diploma' => 3
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
    update new IndividualApplication(
      Id = application.Id,
      Eligibility_Status__c = result.status,
      Eligibility_Notes__c = result.reason,
      Evaluated_Rule__c = rule?.Id,
      Eligibility_Evidence__c = JSON.serialize(evidence),
      Eligibility_Evaluated_On__c = evaluatedOn
    );
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
    Academic_Qualification__c best;
    Integer requiredLevel = LEVELS.get(rule.Qualifying_Level__c);
    for (Academic_Qualification__c candidate : qualifications) {
      if (LEVELS.get(candidate.Level__c) >= requiredLevel) {
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
      List<Entrance_Score__c> scores = [
        SELECT Id, Exam__c, Exam_Year__c, Rank__c, Score__c
        FROM Entrance_Score__c
        WHERE Student__c = :studentId AND Verified__c = TRUE
        WITH SYSTEM_MODE
      ];
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
