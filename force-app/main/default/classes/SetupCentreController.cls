/** Lightning controller for the Set-up Centre (Home page). */
public with sharing class SetupCentreController {
  @AuraEnabled
  public static SetupCentreService.Centre getCentre() {
    try {
      return SetupCentreService.centre();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
