/**
 * Lightning controller for the application workbench and applications queue.
 */
public with sharing class ApplicationController {
  public class ChecklistItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean required;
    @AuraEnabled
    public String instruction;
    @AuraEnabled
    public String rejectReason;
    @AuraEnabled
    public Integer fileCount = 0;
    @AuraEnabled
    public List<ChecklistFile> files = new List<ChecklistFile>();
  }

  /** A file attached to a checklist item, by staff or by the family in the portal. */
  public class ChecklistFile {
    @AuraEnabled
    public Id documentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String extension;
    @AuraEnabled
    public Datetime uploadedOn;
    @AuraEnabled
    public String uploadedBy;
    @AuraEnabled
    public Boolean fromPortal = false;
  }

  public class ApplicationView {
    @AuraEnabled
    public IndividualApplication application;
    @AuraEnabled
    public List<ChecklistItem> checklist = new List<ChecklistItem>();
    @AuraEnabled
    public Boolean canOverrideEligibility;
    @AuraEnabled
    public Integer requiredOpen = 0;
  }

  public class QueueColumn {
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public List<IndividualApplication> applications = new List<IndividualApplication>();
  }

  @AuraEnabled(cacheable=true)
  public static ApplicationView getApplication(Id applicationId) {
    try {
      ApplicationView view = new ApplicationView();
      List<IndividualApplication> rows = [
        SELECT
          Id,
          Name,
          Status,
          AppliedDate,
          ApprovedDate,
          AccountId,
          Account.Name,
          Account.PersonBirthdate,
          Branch__c,
          Branch__r.Name,
          Learning_Course__c,
          Learning_Course__r.Name,
          Learning_Program__r.Name,
          Requested_Offering__c,
          Requested_Offering__r.Name,
          Reviewer__r.Name,
          Eligibility_Status__c,
          Eligibility_Notes__c,
          Checklist_Complete__c,
          Decision__c,
          Decision_Reason__c,
          Decision_Date__c,
          Decided_By__r.Name,
          Offer_Status__c,
          Offer_Expiry_Date__c,
          Offer_Responded_Date__c,
          Source_Enquiry__c,
          WasReturned
        FROM IndividualApplication
        WHERE Id = :applicationId
        WITH USER_MODE
      ];
      if (rows.isEmpty()) {
        throw new AppException('Application not found or not accessible.');
      }
      view.application = rows[0];
      view.canOverrideEligibility = FeatureManagement.checkPermission(
        ApplicationService.OVERRIDE_PERMISSION
      );
      Map<Id, ChecklistItem> items = new Map<Id, ChecklistItem>();
      for (DocumentChecklistItem item : [
        SELECT Id, Name, Status, IsRequired, Instruction, RejectReason
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :applicationId
        WITH USER_MODE
        ORDER BY IsRequired DESC, CreatedDate ASC
      ]) {
        ChecklistItem dto = new ChecklistItem();
        dto.id = item.Id;
        dto.name = item.Name;
        dto.status = item.Status;
        dto.required = item.IsRequired;
        dto.instruction = item.Instruction;
        dto.rejectReason = item.RejectReason;
        items.put(item.Id, dto);
        if (
          item.IsRequired &&
          item.Status != 'Accepted' &&
          item.Status != 'Waived'
        ) {
          view.requiredOpen++;
        }
      }
      if (!items.isEmpty()) {
        for (ContentDocumentLink link : [
          SELECT
            LinkedEntityId,
            ContentDocumentId,
            ContentDocument.Title,
            ContentDocument.FileExtension,
            ContentDocument.LatestPublishedVersion.CreatedDate,
            ContentDocument.LatestPublishedVersion.CreatedBy.Name,
            ContentDocument.LatestPublishedVersion.CreatedBy.ContactId
          FROM ContentDocumentLink
          WHERE LinkedEntityId IN :items.keySet()
          ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC
        ]) {
          ChecklistFile file = new ChecklistFile();
          file.documentId = link.ContentDocumentId;
          file.title = link.ContentDocument.Title;
          file.extension = link.ContentDocument.FileExtension;
          ContentVersion latest = link.ContentDocument.LatestPublishedVersion;
          file.uploadedOn = latest?.CreatedDate;
          file.uploadedBy = latest?.CreatedBy?.Name;
          file.fromPortal = latest?.CreatedBy?.ContactId != null;
          ChecklistItem item = items.get(link.LinkedEntityId);
          item.files.add(file);
          item.fileCount = item.files.size();
        }
      }
      view.checklist = items.values();
      return view;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<QueueColumn> getQueue(Id branchId) {
    try {
      Map<String, QueueColumn> columns = new Map<String, QueueColumn>();
      for (
        String stage : new List<String>{
          'Processing',
          'In Review',
          'Ready For Decision',
          'Offered'
        }
      ) {
        QueueColumn column = new QueueColumn();
        column.stage = stage;
        columns.put(stage, column);
      }
      String query =
        'SELECT Id, Name, Status, Offer_Status__c, Offer_Expiry_Date__c, Account.Name, Learning_Course__r.Name, ' +
        'Branch__r.Name, Checklist_Complete__c, Eligibility_Status__c, AppliedDate, Reviewer__r.Name ' +
        'FROM IndividualApplication WHERE (Status IN (\'Processing\', \'In Review\', \'Ready For Decision\') ' +
        'OR (Status = \'Application Decision\' AND Offer_Status__c = \'Offered\'))';
      if (branchId != null) {
        query += ' AND Branch__c = :branchId';
      }
      query += ' ORDER BY AppliedDate ASC NULLS LAST LIMIT 500';
      for (
        SObject row : Database.queryWithBinds(
          query,
          new Map<String, Object>{ 'branchId' => branchId },
          AccessLevel.USER_MODE
        )
      ) {
        IndividualApplication application = (IndividualApplication) row;
        String stage = application.Status == 'Application Decision'
          ? 'Offered'
          : application.Status;
        columns.get(stage).applications.add(application);
      }
      return columns.values();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void updateChecklistItem(
    Id itemId,
    String status,
    String rejectReason
  ) {
    try {
      ApplicationService.updateChecklistItem(itemId, status, rejectReason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id addChecklistItem(
    Id applicationId,
    String name,
    Boolean required,
    String instruction
  ) {
    try {
      return ApplicationService.addChecklistItem(
        applicationId,
        name,
        required,
        instruction
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void performAction(
    Id applicationId,
    String action,
    String reason
  ) {
    try {
      switch on action {
        when 'submit' {
          ApplicationService.submitForReview(applicationId);
        }
        when 'return' {
          ApplicationService.returnToApplicant(applicationId);
        }
        when 'ready' {
          ApplicationService.markReadyForDecision(applicationId);
        }
        when 'accept' {
          ApplicationService.respondToOffer(applicationId, true);
        }
        when 'decline' {
          ApplicationService.respondToOffer(applicationId, false);
        }
        when 'withdraw' {
          ApplicationService.withdraw(applicationId, reason);
        }
        when 'override' {
          ApplicationService.overrideEligibility(applicationId, reason);
        }
        when else {
          throw new AppException('Unknown action: ' + action);
        }
      }
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void decide(
    Id applicationId,
    String decision,
    String reason,
    Integer offerValidDays
  ) {
    try {
      ApplicationService.decide(
        applicationId,
        decision,
        reason,
        offerValidDays
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
