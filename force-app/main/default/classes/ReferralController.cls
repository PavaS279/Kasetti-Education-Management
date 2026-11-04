/** Lightning controller for the referrals and alumni desk (F4.11). */
public with sharing class ReferralController {
  @AuraEnabled
  public static ReferralService.Desk getDesk(Id branchId) {
    try {
      return ReferralService.desk(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id grantReward(Id referralId) {
    try {
      return ReferralService.reward(referralId, false);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void markNotEligible(Id referralId, String note) {
    try {
      ReferralService.markNotEligible(referralId, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static String referralCode(Id accountId) {
    try {
      return ReferralService.codeFor(accountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer inviteAlumni(List<Id> accountIds, String message) {
    try {
      return ReferralService.inviteAlumni(accountIds, message);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
