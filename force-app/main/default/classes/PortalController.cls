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
}
