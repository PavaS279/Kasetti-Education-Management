/** Normalises discount codes to upper case so look-ups are case-insensitive. */
public with sharing class DiscountTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    normalise((List<Discount__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    normalise((List<Discount__c>) newRecords);
  }

  private static void normalise(List<Discount__c> discounts) {
    for (Discount__c discount : discounts) {
      if (discount.Code__c != null) {
        discount.Code__c = discount.Code__c.trim().toUpperCase();
      }
    }
  }
}
