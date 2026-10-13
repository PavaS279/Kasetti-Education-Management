/** Maintains the campus, college branch, and academic-year uniqueness key. */
public inherited sharing class CampusBranchTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    stamp((List<Campus_Branch__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<Campus_Branch__c>) newRecords);
  }

  private static void stamp(List<Campus_Branch__c> rows) {
    Set<Id> campusIds = new Set<Id>();
    for (Campus_Branch__c row : rows) {
      if (row.Campus__c != null) {
        campusIds.add(row.Campus__c);
      }
    }
    Map<Id, Branch__c> campuses = campusIds.isEmpty()
      ? new Map<Id, Branch__c>()
      : new Map<Id, Branch__c>(
          [
            SELECT Id, Institution_Type__c
            FROM Branch__c
            WHERE Id IN :campusIds
            WITH SYSTEM_MODE
          ]
        );
    for (Campus_Branch__c row : rows) {
      row.Academic_Year__c = row.Academic_Year__c == null
        ? null
        : row.Academic_Year__c.trim();
      Branch__c campus = campuses.get(row.Campus__c);
      if (campus != null && campus.Institution_Type__c != 'College') {
        row.Campus__c.addError('Select a campus configured as a college.');
      }
      row.Unique_Key__c = row.Campus__c == null ||
        row.Branch__c == null ||
        row.Academic_Year__c == null
        ? null
        : String.valueOf(row.Campus__c) +
          '|' +
          String.valueOf(row.Branch__c) +
          '|' +
          row.Academic_Year__c;
      row.Reserved_Regular__c = row.Reserved_Regular__c == null
        ? 0
        : row.Reserved_Regular__c;
      row.Reserved_Lateral__c = row.Reserved_Lateral__c == null
        ? 0
        : row.Reserved_Lateral__c;
      row.Finalised_Regular__c = row.Finalised_Regular__c == null
        ? 0
        : row.Finalised_Regular__c;
      row.Finalised_Lateral__c = row.Finalised_Lateral__c == null
        ? 0
        : row.Finalised_Lateral__c;
    }
  }
}
