/**
 * Lightning controller for the Learner 360 record page component.
 */
public with sharing class Learner360Controller {
  @AuraEnabled(cacheable=true)
  public static LearnerService.Learner360 getLearner360(Id accountId) {
    try {
      return LearnerService.getLearner360(accountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id addGuardian(
    Id learnerAccountId,
    LearnerService.GuardianInput input
  ) {
    try {
      return LearnerService.addGuardian(learnerAccountId, input);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void updateGuardianLink(
    Id relationId,
    LearnerService.GuardianInput input
  ) {
    try {
      LearnerService.updateGuardianLink(relationId, input);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void endGuardianLink(Id relationId) {
    try {
      LearnerService.endGuardianLink(relationId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void updatePreferences(
    Id accountId,
    LearnerService.PreferenceInput input
  ) {
    try {
      LearnerService.updatePreferences(accountId, input);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<Account> searchPeople(String term) {
    try {
      return LearnerService.searchPeople(term);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
