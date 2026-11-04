/**
 * Lightning controller for the enquiry pipeline board and enquiry workbench.
 */
public with sharing class EnquiryController {
  public static final List<String> PIPELINE_STATUSES = new List<String>{
    'New',
    'Contacted',
    'Nurturing'
  };

  public class PipelineColumn {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public List<Lead> enquiries = new List<Lead>();
  }

  @AuraEnabled(cacheable=true)
  public static List<PipelineColumn> getPipeline(
    Id branchId,
    Boolean mineOnly
  ) {
    try {
      Id userId = UserInfo.getUserId();
      String query =
        'SELECT Id, Name, FirstName, LastName, Status, Email, Phone, MobilePhone, Enquiry_Channel__c, Branch__r.Name, ' +
        'Interested_Course__r.Name, Interested_Program__r.Name, Next_Follow_Up__c, Follow_Up_Status__c, ' +
        'Possible_Duplicate__c, Owner.Name, CreatedDate, Trial_Session_Date__c ' +
        'FROM Lead WHERE IsConverted = FALSE AND Status IN :PIPELINE_STATUSES';
      if (branchId != null) {
        query += ' AND Branch__c = :branchId';
      }
      if (mineOnly == true) {
        query += ' AND OwnerId = :userId';
      }
      query += ' ORDER BY Next_Follow_Up__c ASC NULLS LAST, CreatedDate DESC LIMIT 600';
      Map<String, PipelineColumn> columns = new Map<String, PipelineColumn>();
      for (String status : PIPELINE_STATUSES) {
        PipelineColumn column = new PipelineColumn();
        column.status = status;
        columns.put(status, column);
      }
      for (
        SObject row : Database.queryWithBinds(
          query,
          new Map<String, Object>{
            'PIPELINE_STATUSES' => PIPELINE_STATUSES,
            'branchId' => branchId,
            'userId' => userId
          },
          AccessLevel.USER_MODE
        )
      ) {
        Lead enquiry = (Lead) row;
        columns.get(enquiry.Status).enquiries.add(enquiry);
      }
      return columns.values();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Branch__c> getBranches() {
    try {
      return [
        SELECT Id, Name, Branch_Code__c
        FROM Branch__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ];
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void updateStatus(Id leadId, String status, String lostReason) {
    try {
      if (status == 'Qualified') {
        throw new AppException('Use Convert to qualify an enquiry.');
      }
      Lead enquiry = new Lead(Id = leadId, Status = status);
      if (status == 'Unqualified') {
        enquiry.Lost_Reason__c = lostReason;
      }
      Database.update(enquiry, AccessLevel.USER_MODE);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Records a completed follow-up activity and schedules the next one. */
  @AuraEnabled
  public static void logFollowUp(
    Id leadId,
    String outcome,
    String notes,
    Datetime nextFollowUp
  ) {
    try {
      Lead enquiry = [
        SELECT Id, Status, OwnerId
        FROM Lead
        WHERE Id = :leadId
        WITH USER_MODE
      ];
      Savepoint sp = Database.setSavepoint();
      try {
        Database.insert(
          new Task(
            WhoId = leadId,
            Subject = 'Follow-up: ' + outcome,
            Description = notes,
            Status = 'Completed',
            ActivityDate = Date.today(),
            TaskSubtype = 'Call'
          ),
          AccessLevel.USER_MODE
        );
        Lead changes = new Lead(
          Id = leadId,
          Last_Contacted__c = System.now(),
          Next_Follow_Up__c = nextFollowUp
        );
        if (enquiry.Status == 'New') {
          changes.Status = 'Contacted';
        }
        Database.update(changes, AccessLevel.USER_MODE);
      } catch (Exception failure) {
        Database.rollback(sp);
        throw failure;
      }
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static EnquiryConversionService.ConversionPreview getConversionPreview(
    Id leadId
  ) {
    try {
      return EnquiryConversionService.preview(leadId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static EnquiryConversionService.ConversionResult convertEnquiry(
    EnquiryConversionService.ConversionRequest request
  ) {
    try {
      return EnquiryConversionService.convert(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
