public without sharing class AdmissionRuleTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> records) {
    stamp((List<Admission_Rule__c>) records, true);
  }
  protected override void beforeUpdate(
    List<SObject> records,
    Map<Id, SObject> oldMap
  ) {
    for (Admission_Rule__c rule : (List<Admission_Rule__c>) records) {
      Admission_Rule__c oldRule = (Admission_Rule__c) oldMap.get(rule.Id);
      if (
        oldRule.Status__c != 'Draft' && !AdmissionRuleService.isLifecycleUpdate
      )
        rule.addError(
          'Active, superseded and retired admission rules cannot be edited. Clone a new draft.'
        );
    }
    stamp((List<Admission_Rule__c>) records, false);
  }
  private static void stamp(List<Admission_Rule__c> rules, Boolean isInsert) {
    Set<String> ruleKeys = new Set<String>();
    for (Admission_Rule__c rule : rules) {
      rule.Academic_Year__c = rule.Academic_Year__c?.trim();
      rule.Rule_Key__c =
        String.valueOf(rule.Branch__c) +
        '|' +
        rule.Academic_Year__c +
        '|' +
        rule.Entry_Route__c +
        '|' +
        (rule.Campus__c == null ? 'ALL' : String.valueOf(rule.Campus__c));
      ruleKeys.add(rule.Rule_Key__c);
    }
    Map<String, Decimal> maxVersion = new Map<String, Decimal>();
    Map<String, Object> queryBinds = new Map<String, Object>{
      'ruleKeys' => ruleKeys
    };
    List<Admission_Rule__c> existingRules = Database.queryWithBinds(
      'SELECT Rule_Key__c, Version__c FROM Admission_Rule__c WHERE Rule_Key__c IN :ruleKeys ORDER BY Version__c DESC',
      queryBinds,
      AccessLevel.SYSTEM_MODE
    );
    for (Admission_Rule__c existing : existingRules) {
      if (!maxVersion.containsKey(existing.Rule_Key__c)) {
        maxVersion.put(existing.Rule_Key__c, existing.Version__c);
      }
    }
    for (Admission_Rule__c rule : rules) {
      if (isInsert) {
        Decimal nextVersion =
          (maxVersion.containsKey(rule.Rule_Key__c)
            ? maxVersion.get(rule.Rule_Key__c)
            : 0) + 1;
        rule.Version__c = nextVersion;
        maxVersion.put(rule.Rule_Key__c, nextVersion);
      }
      rule.Version_Key__c = rule.Rule_Key__c + '#' + rule.Version__c;
      rule.Active_Key__c = rule.Status__c == 'Active' ? rule.Rule_Key__c : null;
    }
  }
}
