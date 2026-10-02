/**
 * Enforces allowed status transitions declared in Status_Transition__mdt.
 * Any change of a governed field that is not declared adds a record error.
 * Fields with no declared transitions are not governed.
 */
public inherited sharing class StatusTransitionService {
  @TestVisible
  private static List<Status_Transition__mdt> testTransitions;
  private static Map<String, Set<String>> allowedByField;

  public static void validate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap,
    SObjectField field
  ) {
    if (oldMap == null) {
      return;
    }
    String objectName = newRecords.getSObjectType().getDescribe().getName();
    String key = (objectName +
      '.' +
      field.getDescribe().getName())
      .toLowerCase();
    Set<String> allowed = getAllowed().get(key);
    if (allowed == null) {
      return;
    }
    for (SObject record : newRecords) {
      Object fromValue = oldMap.get(record.Id).get(field);
      Object toValue = record.get(field);
      if (fromValue == toValue) {
        continue;
      }
      String transition = (String.valueOf(fromValue) +
        '->' +
        String.valueOf(toValue))
        .toLowerCase();
      if (!allowed.contains(transition)) {
        record.addError(
          field,
          String.format(
            System.Label.KEM_Invalid_Status_Transition,
            new List<Object>{ fromValue, toValue }
          )
        );
      }
    }
  }

  public static Boolean isAllowed(
    SObjectType objectType,
    SObjectField field,
    String fromValue,
    String toValue
  ) {
    String key = (objectType.getDescribe().getName() +
      '.' +
      field.getDescribe().getName())
      .toLowerCase();
    Set<String> allowed = getAllowed().get(key);
    return allowed == null ||
      fromValue == toValue ||
      allowed.contains((fromValue + '->' + toValue).toLowerCase());
  }

  private static Map<String, Set<String>> getAllowed() {
    if (allowedByField == null) {
      allowedByField = new Map<String, Set<String>>();
      List<Status_Transition__mdt> transitions = testTransitions != null
        ? testTransitions
        : Status_Transition__mdt.getAll().values();
      for (Status_Transition__mdt t : transitions) {
        if (!t.Active__c) {
          continue;
        }
        String key = (t.Object_Name__c + '.' + t.Field_Name__c).toLowerCase();
        if (!allowedByField.containsKey(key)) {
          allowedByField.put(key, new Set<String>());
        }
        allowedByField.get(key)
          .add((t.From_Status__c + '->' + t.To_Status__c).toLowerCase());
      }
    }
    return allowedByField;
  }
}
