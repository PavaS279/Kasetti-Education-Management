/** College admission checklist snapshots and privacy-consent audit. */
public with sharing class CollegeDocumentService {
  @TestVisible
  private static Boolean suppressStatusUpdates = false;
  public static void createChecklists(Set<Id> applicationIds) {
    if (applicationIds.isEmpty()) {
      return;
    }
    Map<Id, IndividualApplication> applications = new Map<Id, IndividualApplication>(
      [
        SELECT
          Id,
          AccountId,
          Learning_Program__c,
          Entry_Route__c,
          Academic_Year__c
        FROM IndividualApplication
        WHERE Id IN :applicationIds
        WITH SYSTEM_MODE
      ]
    );
    Set<Id> existing = new Set<Id>();
    for (DocumentChecklistItem item : [
      SELECT ParentRecordId
      FROM DocumentChecklistItem
      WHERE ParentRecordId IN :applicationIds
      WITH SYSTEM_MODE
    ]) {
      existing.add(item.ParentRecordId);
    }
    Set<Id> studentIds = new Set<Id>();
    for (IndividualApplication application : applications.values()) {
      if (!existing.contains(application.Id) && application.AccountId != null) {
        studentIds.add(application.AccountId);
      }
    }
    Map<Id, Set<String>> levelsByStudent = new Map<Id, Set<String>>();
    for (Academic_Qualification__c qualification : [
      SELECT Student__c, Level__c
      FROM Academic_Qualification__c
      WHERE Student__c IN :studentIds AND Verified__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (!levelsByStudent.containsKey(qualification.Student__c)) {
        levelsByStudent.put(qualification.Student__c, new Set<String>());
      }
      levelsByStudent.get(qualification.Student__c).add(qualification.Level__c);
    }
    List<Admission_Document_Rule__c> rules = [
      SELECT
        Id,
        Programme__c,
        Entry_Route__c,
        Qualifying_Level__c,
        Academic_Year__c,
        Document_Type__c,
        Label__c,
        Instruction__c,
        Required__c,
        Sensitive_Class__c,
        Retain_File__c,
        Retention_Days__c,
        AI_Extractable__c
      FROM Admission_Document_Rule__c
      WHERE Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Sort_Order__c, CreatedDate
    ];
    List<DocumentChecklistItem> items = new List<DocumentChecklistItem>();
    for (IndividualApplication application : applications.values()) {
      if (existing.contains(application.Id)) {
        continue;
      }
      Set<String> levels = levelsByStudent.get(application.AccountId);
      for (Admission_Document_Rule__c rule : rules) {
        if (!matches(application, levels, rule)) {
          continue;
        }
        items.add(
          new DocumentChecklistItem(
            Name = rule.Label__c.left(255),
            ParentRecordId = application.Id,
            IsRequired = rule.Required__c,
            Instruction = rule.Instruction__c,
            Status = 'New',
            Document_Rule__c = rule.Id,
            Document_Type__c = rule.Document_Type__c,
            Sensitive_Class__c = rule.Sensitive_Class__c,
            Retain_File__c = rule.Retain_File__c,
            Retention_Days__c = rule.Retention_Days__c,
            AI_Extractable__c = rule.AI_Extractable__c
          )
        );
      }
    }
    if (!items.isEmpty()) {
      Database.insert(items, AccessLevel.SYSTEM_MODE);
    }
  }

  public static void captureConsent(Id applicationId) {
    if (!Schema.SObjectType.IndividualApplication.isUpdateable()) {
      throw new AppException(
        'You do not have permission to update this admission.'
      );
    }
    IndividualApplication application = [
      SELECT Id, College_Mode__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (!application.College_Mode__c) {
      throw new AppException(
        'Privacy consent applies only to college admissions.'
      );
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        Privacy_Consent__c = true,
        Consent_Captured_On__c = System.now(),
        Consent_Captured_By__c = UserInfo.getUserId()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static void markDocumentsVerified(Id applicationId) {
    RecordAccess.assertEditable(applicationId);
    IndividualApplication application = [
      SELECT Id, College_Mode__c, Privacy_Consent__c, Eligibility_Status__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (!application.College_Mode__c) {
      throw new AppException(
        'Document verification applies only to college admissions.'
      );
    }
    if (!application.Privacy_Consent__c) {
      throw new AppException(
        'Capture privacy consent before verifying documents.'
      );
    }
    if (
      application.Eligibility_Status__c != 'Eligible' &&
      application.Eligibility_Status__c != 'Overridden'
    ) {
      throw new AppException(
        'The admission must be eligible before documents are verified.'
      );
    }
    for (DocumentChecklistItem item : [
      SELECT Name, Status
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :applicationId AND IsRequired = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (item.Status != 'Accepted' && item.Status != 'Waived') {
        throw new AppException(item.Name + ' has not been verified.');
      }
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = 'Documents Verified'
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static void verify(Id checklistItemId, String last4) {
    if (!Schema.SObjectType.DocumentChecklistItem.isUpdateable()) {
      throw new AppException('You do not have permission to verify documents.');
    }
    DocumentChecklistItem item = [
      SELECT Id, ParentRecordId, Sensitive_Class__c, Retain_File__c
      FROM DocumentChecklistItem
      WHERE Id = :checklistItemId
      WITH SYSTEM_MODE
    ];
    IndividualApplication admission = [
      SELECT Privacy_Consent__c
      FROM IndividualApplication
      WHERE Id = :item.ParentRecordId
      WITH SYSTEM_MODE
    ];
    if (!admission.Privacy_Consent__c) {
      throw new AppException(
        'Capture privacy consent before verifying documents.'
      );
    }
    Boolean identity = item.Sensitive_Class__c == 'Identity';
    String cleanLast4 = String.isBlank(last4) ? null : last4.trim();
    if (
      identity &&
      (cleanLast4 == null || !Pattern.matches('^[0-9]{4}$', cleanLast4))
    ) {
      throw new AppException(
        'Enter only the last four digits of the identity number.'
      );
    }
    Database.update(
      new DocumentChecklistItem(
        Id = item.Id,
        Last4__c = identity ? cleanLast4 : null,
        Verified_By__c = UserInfo.getUserId(),
        Verified_On__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
    if (!suppressStatusUpdates) {
      ChecklistItemGateway.updateStatusAsSystem(
        new List<DocumentChecklistItem>{
          new DocumentChecklistItem(Id = item.Id, Status = 'Accepted')
        }
      );
    }
    if (identity || !item.Retain_File__c) {
      deleteFiles(item.Id);
      Database.update(
        new DocumentChecklistItem(
          Id = item.Id,
          File_Deleted_On__c = System.now()
        ),
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  private static void deleteFiles(Id checklistItemId) {
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :checklistItemId
      WITH SYSTEM_MODE
    ]) {
      documentIds.add(link.ContentDocumentId);
    }
    if (!documentIds.isEmpty()) {
      List<ContentDocument> documents = [
        SELECT Id
        FROM ContentDocument
        WHERE Id IN :documentIds
        WITH SYSTEM_MODE
      ];
      Database.delete(documents, false);
    }
  }

  public static void deleteExpiredFiles(
    List<DocumentChecklistItem> candidates
  ) {
    List<DocumentChecklistItem> audited = new List<DocumentChecklistItem>();
    Datetime nowValue = System.now();
    for (DocumentChecklistItem item : candidates) {
      if (
        item.Verified_On__c == null ||
        item.Retention_Days__c == null ||
        item.File_Deleted_On__c != null ||
        item.Verified_On__c.addDays(item.Retention_Days__c.intValue()) >
        nowValue
      ) {
        continue;
      }
      deleteFiles(item.Id);
      audited.add(
        new DocumentChecklistItem(Id = item.Id, File_Deleted_On__c = nowValue)
      );
    }
    if (!audited.isEmpty()) {
      Database.update(audited, AccessLevel.SYSTEM_MODE);
    }
  }

  private static Boolean matches(
    IndividualApplication application,
    Set<String> levels,
    Admission_Document_Rule__c rule
  ) {
    return (rule.Programme__c == null ||
      rule.Programme__c == application.Learning_Program__c) &&
      (String.isBlank(rule.Entry_Route__c) ||
      rule.Entry_Route__c == application.Entry_Route__c) &&
      rule.Academic_Year__c == application.Academic_Year__c &&
      (String.isBlank(rule.Qualifying_Level__c) ||
      (levels != null && levels.contains(rule.Qualifying_Level__c)));
  }
}
