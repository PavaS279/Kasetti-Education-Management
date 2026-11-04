/** Lightning controller for the learner and guardian portal (see PortalService). */
public with sharing class PortalController {
  @AuraEnabled
  public static PortalService.Home getHome() {
    try {
      return PortalService.home();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PortalService.LearnerDetail getLearner(Id learnerContactId) {
    try {
      return PortalService.learner(learnerContactId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void markMessageRead(Id messageId) {
    try {
      PortalService.markMessageRead(messageId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PortalService.DocumentFile downloadDocument(Id versionId) {
    try {
      return PortalService.downloadDocument(versionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PaymentLinkService.LinkView startPayment(Id invoiceId) {
    try {
      return PaymentLinkService.createForPortal(invoiceId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Upload only: families attach admission documents; staff review them. */
  @AuraEnabled
  public static Id uploadAdmissionDocument(
    Id itemId,
    String fileName,
    String base64
  ) {
    try {
      return PortalService.uploadAdmissionDocument(itemId, fileName, base64);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PortalService.ReferralInfo getReferral(Boolean create) {
    try {
      return PortalService.referral(create);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
