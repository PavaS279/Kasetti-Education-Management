/**
 * Prevents overlapping active prices for the same course, branch scope,
 * delivery mode scope, fee type, and billing frequency.
 */
public with sharing class FeePriceTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    validateNoOverlap((List<Fee_Price__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    validateNoOverlap((List<Fee_Price__c>) newRecords);
  }

  private static void validateNoOverlap(List<Fee_Price__c> prices) {
    Set<Id> courseIds = new Set<Id>();
    for (Fee_Price__c price : prices) {
      if (price.Active__c && price.Learning_Course__c != null) {
        courseIds.add(price.Learning_Course__c);
      }
    }
    if (courseIds.isEmpty()) {
      return;
    }
    List<Fee_Price__c> existing = [
      SELECT
        Id,
        Name,
        Learning_Course__c,
        Branch__c,
        Delivery_Mode__c,
        Fee_Type__c,
        Billing_Frequency__c,
        Effective_From__c,
        Effective_To__c
      FROM Fee_Price__c
      WHERE Learning_Course__c IN :courseIds AND Active__c = TRUE
      WITH SYSTEM_MODE
    ];
    List<Fee_Price__c> candidates = new List<Fee_Price__c>(existing);
    for (Fee_Price__c price : prices) {
      if (!price.Active__c || price.Learning_Course__c == null) {
        continue;
      }
      for (Fee_Price__c other : candidates) {
        if (other === price || (price.Id != null && other.Id == price.Id)) {
          continue;
        }
        if (sameScope(price, other) && overlaps(price, other)) {
          price.addError(
            'An active ' +
              price.Fee_Type__c +
              ' price already covers these dates for the same course, branch, and delivery mode' +
              (other.Name == null ? '' : ' (' + other.Name + ')') +
              '. End the existing price first.'
          );
          break;
        }
      }
      candidates.add(price);
    }
  }

  private static Boolean sameScope(Fee_Price__c a, Fee_Price__c b) {
    return a.Learning_Course__c == b.Learning_Course__c &&
      a.Branch__c == b.Branch__c &&
      a.Delivery_Mode__c == b.Delivery_Mode__c &&
      a.Fee_Type__c == b.Fee_Type__c &&
      a.Billing_Frequency__c == b.Billing_Frequency__c;
  }

  private static Boolean overlaps(Fee_Price__c a, Fee_Price__c b) {
    Date aEnd = a.Effective_To__c == null
      ? Date.newInstance(4000, 12, 31)
      : a.Effective_To__c;
    Date bEnd = b.Effective_To__c == null
      ? Date.newInstance(4000, 12, 31)
      : b.Effective_To__c;
    return a.Effective_From__c <= bEnd && b.Effective_From__c <= aEnd;
  }
}
