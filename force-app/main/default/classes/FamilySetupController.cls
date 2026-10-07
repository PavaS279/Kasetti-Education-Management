/** Lightning controller for New family (walk-in) and New application. */
public with sharing class FamilySetupController {
  @AuraEnabled
  public static FamilySetupService.Choices getChoices(Id branchId) {
    try {
      return FamilySetupService.choices(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<FamilySetupService.Match> findMatches(
    FamilySetupService.FamilyRequest request
  ) {
    try {
      return FamilySetupService.findMatches(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static FamilySetupService.FamilyResult createFamily(
    FamilySetupService.FamilyRequest request
  ) {
    try {
      return FamilySetupService.createFamily(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id createApplication(
    Id learnerId,
    Id branchId,
    Id courseId,
    Id offeringId
  ) {
    try {
      return FamilySetupService.newApplication(
        learnerId,
        branchId,
        courseId,
        offeringId
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
