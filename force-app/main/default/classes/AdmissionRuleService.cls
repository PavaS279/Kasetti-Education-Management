public with sharing class AdmissionRuleService {
  @TestVisible
  public static Boolean isLifecycleUpdate = false;
  public static void activate(Id ruleId) {
    Admission_Rule__c draft = [
      SELECT Id, Rule_Key__c, Status__c, Entrance_Required__c
      FROM Admission_Rule__c
      WHERE Id = :ruleId
      WITH USER_MODE
      FOR UPDATE
    ];
    if (draft.Status__c != 'Draft')
      throw new AppException('Only a draft admission rule can be activated.');
    if (
      draft.Entrance_Required__c &&
      [
        SELECT COUNT()
        FROM Admission_Rule_Entrance__c
        WHERE Admission_Rule__c = :ruleId
      ] == 0
    )
      throw new AppException(
        'Add at least one accepted entrance exam before activation.'
      );
    List<Admission_Rule__c> changes = new List<Admission_Rule__c>();
    Datetime now = System.now();
    for (Admission_Rule__c active : [
      SELECT Id
      FROM Admission_Rule__c
      WHERE Rule_Key__c = :draft.Rule_Key__c AND Status__c = 'Active'
      FOR UPDATE
    ])
      changes.add(
        new Admission_Rule__c(
          Id = active.Id,
          Status__c = 'Superseded',
          Effective_To__c = now,
          Active_Key__c = null
        )
      );
    changes.add(
      new Admission_Rule__c(
        Id = draft.Id,
        Status__c = 'Active',
        Effective_From__c = now,
        Active_Key__c = draft.Rule_Key__c
      )
    );
    isLifecycleUpdate = true;
    try {
      Database.update(changes, AccessLevel.SYSTEM_MODE);
    } finally {
      isLifecycleUpdate = false;
    }
  }

  public static Id cloneAsDraft(Id sourceRuleId) {
    if (!Admission_Rule__c.SObjectType.getDescribe().isCreateable()) {
      throw new AppException(
        'You do not have permission to create admission rules.'
      );
    }
    Admission_Rule__c source = [
      SELECT
        Branch__c,
        Campus__c,
        Academic_Year__c,
        Entry_Route__c,
        Entry_Year_Of_Study__c,
        Qualifying_Level__c,
        Qualifying_Streams__c,
        Qualifying_Branch_Codes__c,
        Min_Percentage__c,
        Entrance_Required__c,
        Interview_Required__c
      FROM Admission_Rule__c
      WHERE Id = :sourceRuleId
      WITH USER_MODE
    ];
    Admission_Rule__c draft = source.clone(false, false, false, false);
    draft.Status__c = 'Draft';
    draft.Effective_From__c = null;
    draft.Effective_To__c = null;
    draft.Used__c = false;
    Database.insert(draft, AccessLevel.SYSTEM_MODE);

    List<Admission_Rule_Entrance__c> copies = new List<Admission_Rule_Entrance__c>();
    for (Admission_Rule_Entrance__c accepted : [
      SELECT
        Entrance_Exam__c,
        Max_Rank__c,
        Min_Score__c,
        Exam_Year_From__c,
        Exam_Year_To__c
      FROM Admission_Rule_Entrance__c
      WHERE Admission_Rule__c = :sourceRuleId
      WITH SYSTEM_MODE
    ]) {
      copies.add(
        new Admission_Rule_Entrance__c(
          Admission_Rule__c = draft.Id,
          Entrance_Exam__c = accepted.Entrance_Exam__c,
          Max_Rank__c = accepted.Max_Rank__c,
          Min_Score__c = accepted.Min_Score__c,
          Exam_Year_From__c = accepted.Exam_Year_From__c,
          Exam_Year_To__c = accepted.Exam_Year_To__c
        )
      );
    }
    if (!copies.isEmpty()) {
      Database.insert(copies, AccessLevel.SYSTEM_MODE);
    }
    return draft.Id;
  }

  public static void retire(Id ruleId) {
    Admission_Rule__c active = [
      SELECT Id, Status__c
      FROM Admission_Rule__c
      WHERE Id = :ruleId
      WITH USER_MODE
      FOR UPDATE
    ];
    if (active.Status__c != 'Active') {
      throw new AppException('Only an active admission rule can be retired.');
    }
    isLifecycleUpdate = true;
    try {
      Database.update(
        new Admission_Rule__c(
          Id = active.Id,
          Status__c = 'Retired',
          Effective_To__c = System.now(),
          Active_Key__c = null
        ),
        AccessLevel.SYSTEM_MODE
      );
    } finally {
      isLifecycleUpdate = false;
    }
  }

  /** Marks a rule version as used. Runs for any user whose admission is evaluated, so it ignores record sharing. */
  public static void markUsed(Id ruleId) {
    isLifecycleUpdate = true;
    try {
      new SystemWriter().markUsed(ruleId);
    } finally {
      isLifecycleUpdate = false;
    }
  }

  private without sharing class SystemWriter {
    void markUsed(Id ruleId) {
      Database.update(
        new Admission_Rule__c(Id = ruleId, Used__c = true),
        AccessLevel.SYSTEM_MODE
      );
    }
  }
}
