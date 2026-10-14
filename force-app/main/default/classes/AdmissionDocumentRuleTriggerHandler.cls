public without sharing class AdmissionDocumentRuleTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> records) {
    stamp((List<Admission_Document_Rule__c>) records);
  }
  protected override void beforeUpdate(
    List<SObject> records,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<Admission_Document_Rule__c>) records);
  }
  private static void stamp(List<Admission_Document_Rule__c> records) {
    for (Admission_Document_Rule__c value : records) {
      value.Academic_Year__c = value.Academic_Year__c?.trim();
      value.Document_Type__c = value.Document_Type__c?.trim();
      value.Unique_Key__c =
        String.valueOf(value.Programme__c) +
        '|' +
        (String.isBlank(value.Entry_Route__c) ? 'ALL' : value.Entry_Route__c) +
        '|' +
        (String.isBlank(value.Qualifying_Level__c)
          ? 'ALL'
          : value.Qualifying_Level__c) +
        '|' +
        value.Academic_Year__c +
        '|' +
        value.Document_Type__c?.toLowerCase();
    }
  }
}
