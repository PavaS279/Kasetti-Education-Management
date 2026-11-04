public without sharing class AdmissionRuleEntranceTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> records) {
    stamp((List<Admission_Rule_Entrance__c>) records);
  }
  protected override void beforeUpdate(
    List<SObject> records,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<Admission_Rule_Entrance__c>) records);
  }
  protected override void beforeDelete(List<SObject> records) {
    Set<Id> ruleIds = new Set<Id>();
    for (
      Admission_Rule_Entrance__c row : (List<Admission_Rule_Entrance__c>) records
    )
      ruleIds.add(row.Admission_Rule__c);
    Map<Id, Admission_Rule__c> rules = new Map<Id, Admission_Rule__c>(
      [SELECT Id, Status__c FROM Admission_Rule__c WHERE Id IN :ruleIds]
    );
    for (
      Admission_Rule_Entrance__c row : (List<Admission_Rule_Entrance__c>) records
    )
      if (rules.get(row.Admission_Rule__c)?.Status__c != 'Draft')
        row.addError('Accepted entrances can only be changed on a draft rule.');
  }
  private static void stamp(List<Admission_Rule_Entrance__c> rows) {
    Set<Id> ruleIds = new Set<Id>();
    for (Admission_Rule_Entrance__c row : rows)
      ruleIds.add(row.Admission_Rule__c);
    Map<Id, Admission_Rule__c> rules = new Map<Id, Admission_Rule__c>(
      [SELECT Id, Status__c FROM Admission_Rule__c WHERE Id IN :ruleIds]
    );
    for (Admission_Rule_Entrance__c row : rows) {
      if (rules.get(row.Admission_Rule__c)?.Status__c != 'Draft')
        row.addError('Accepted entrances can only be changed on a draft rule.');
      row.Unique_Key__c =
        String.valueOf(row.Admission_Rule__c) +
        '|' +
        row.Entrance_Exam__c;
    }
  }
}
