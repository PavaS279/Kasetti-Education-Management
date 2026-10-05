/** Lightning controller for class waitlists. */
public with sharing class WaitlistController {
  @AuraEnabled
  public static WaitlistService.Waitlist getWaitlist(Id offeringId) {
    try {
      return WaitlistService.getWaitlist(offeringId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<WaitlistService.Entry> getLearnerWaitlist(
    Id learnerAccountId
  ) {
    try {
      return WaitlistService.learnerEntries(learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id joinWaitlist(WaitlistService.JoinRequest request) {
    try {
      return WaitlistService.join(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id acceptOffer(Id entryId) {
    try {
      return WaitlistService.accept(entryId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void declineOffer(Id entryId, String reason) {
    try {
      WaitlistService.decline(entryId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void removeFromWaitlist(Id entryId, String reason) {
    try {
      WaitlistService.cancel(entryId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void requeue(Id entryId) {
    try {
      WaitlistService.requeue(entryId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
