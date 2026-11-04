/** Lightning controller for the Kasetti home page insights. */
public with sharing class InsightsController {
  @AuraEnabled
  public static InsightsService.Insights getInsights() {
    try {
      return InsightsService.load();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
