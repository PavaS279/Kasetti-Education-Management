/**
 * Persists Log_Event__e platform events to Error_Log__c. Runs as the
 * Automated Process user, so it is intentionally without sharing.
 */
public without sharing class LogEventTriggerHandler extends TriggerHandler {
  protected override void afterInsert(List<SObject> newRecords) {
    List<Error_Log__c> logs = new List<Error_Log__c>();
    for (Log_Event__e event : (List<Log_Event__e>) newRecords) {
      logs.add(
        new Error_Log__c(
          Severity__c = event.Severity__c,
          Source__c = event.Source__c,
          Message__c = event.Message__c,
          Exception_Type__c = event.Exception_Type__c,
          Stack_Trace__c = event.Stack_Trace__c,
          Record_Id__c = event.Record_Id__c,
          Context__c = event.Context__c,
          Transaction_Id__c = event.Transaction_Id__c,
          Running_User__c = event.Running_User_Id__c
        )
      );
    }
    // Partial success: one malformed entry must not drop the rest.
    Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
  }
}
