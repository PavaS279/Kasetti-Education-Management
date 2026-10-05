/** Lightning controller for course grades, report card comments and finalisation. */
public with sharing class GradingController {
  @AuraEnabled
  public static GradingService.ClassGrades getClassGrades(Id offeringId) {
    try {
      return GradingService.classGrades(offeringId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void saveWeights(
    Id offeringId,
    List<GradingService.WeightRow> weights
  ) {
    try {
      GradingService.saveWeights(offeringId, weights);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void saveComments(
    Id offeringId,
    List<GradingService.CommentRow> comments
  ) {
    try {
      GradingService.saveComments(offeringId, comments);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer finaliseGrades(Id offeringId) {
    try {
      return GradingService.finalise(offeringId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void reopenGrades(Id offeringId, String reason) {
    try {
      GradingService.reopen(offeringId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
