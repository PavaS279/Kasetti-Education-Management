/** Nightly deletion of verified college admission files whose retention elapsed. */
public without sharing class CollegeDocumentRetentionJob implements Database.Batchable<SObject>, Schedulable {
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Verified_On__c, Retention_Days__c, File_Deleted_On__c
        FROM DocumentChecklistItem
        WHERE
          Verified_On__c != NULL
          AND Retention_Days__c != NULL
          AND File_Deleted_On__c = NULL
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<DocumentChecklistItem> scope
  ) {
    CollegeDocumentService.deleteExpiredFiles(scope);
  }

  public void finish(Database.BatchableContext context) {
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(this, 100);
  }
}
