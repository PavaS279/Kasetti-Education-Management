/** Lightning controller for course pricing and the quote simulator. */
public with sharing class PricingController {
  @AuraEnabled(cacheable=true)
  public static List<Fee_Price__c> getCoursePrices(Id courseId) {
    try {
      return [
        SELECT
          Id,
          Name,
          Fee_Type__c,
          Billing_Frequency__c,
          Amount__c,
          Branch__c,
          Branch__r.Name,
          Delivery_Mode__c,
          Effective_From__c,
          Effective_To__c,
          Active__c,
          Description__c
        FROM Fee_Price__c
        WHERE Learning_Course__c = :courseId
        WITH USER_MODE
        ORDER BY Active__c DESC, Effective_From__c DESC
        LIMIT 200
      ];
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PricingService.Quote getQuote(
    PricingService.QuoteRequest request
  ) {
    try {
      return PricingService.quote(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Ends a price (sets Effective To) so a replacement can start the next day. */
  @AuraEnabled
  public static void endPrice(Id priceId, Date endDate) {
    try {
      Database.update(
        new Fee_Price__c(Id = priceId, Effective_To__c = endDate),
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
