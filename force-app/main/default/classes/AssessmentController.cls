/** Lightning controller for the gradebook and class assessments. */
public with sharing class AssessmentController {
  @AuraEnabled
  public static AssessmentService.Gradebook getGradebook(Id assessmentId) {
    try {
      return AssessmentService.getGradebook(assessmentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void saveResults(
    Id assessmentId,
    List<AssessmentService.ResultRow> rows
  ) {
    try {
      AssessmentService.saveResults(assessmentId, rows);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void publish(Id assessmentId) {
    try {
      AssessmentService.publish(assessmentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Course_Assessment__c> getClassAssessments(Id offeringId) {
    try {
      return [
        SELECT
          Id,
          Name,
          Assessment_Type__c,
          Max_Score__c,
          Weight__c,
          Assessment_Date__c,
          Status__c,
          Average_Percentage__c
        FROM Course_Assessment__c
        WHERE Course_Offering__c = :offeringId
        WITH USER_MODE
        ORDER BY Assessment_Date__c DESC NULLS LAST
      ];
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Assessment_Result__c> getLearnerResults(
    Id learnerAccountId
  ) {
    try {
      Account learner = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :learnerAccountId
        WITH USER_MODE
      ];
      return AssessmentService.publishedResults(learner.PersonContactId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
