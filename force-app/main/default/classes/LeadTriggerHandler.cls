/**
 * Enquiry (Lead) record rules: branch-based assignment, duplicate flagging,
 * governed status transitions, contact tracking, and the first follow-up task.
 */
public with sharing class LeadTriggerHandler extends TriggerHandler {
  @TestVisible
  private static final Integer FIRST_CONTACT_HOURS = 24;

  protected override void beforeInsert(List<SObject> newRecords) {
    List<Lead> leads = (List<Lead>) newRecords;
    EnquiryAssignmentService.assign(leads);
    EnquiryDuplicateService.flagDuplicates(leads);
    ReferralService.resolveCodes(leads);
    for (Lead enquiry : leads) {
      if (enquiry.Branch__c != null && enquiry.Next_Follow_Up__c == null) {
        enquiry.Next_Follow_Up__c = System.now().addHours(FIRST_CONTACT_HOURS);
      }
    }
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    StatusTransitionService.validate(newRecords, oldMap, Lead.Status);
    List<Lead> contactChanged = (List<Lead>) changedRecords(
      newRecords,
      oldMap,
      new List<SObjectField>{ Lead.Email, Lead.Phone, Lead.MobilePhone }
    );
    if (!contactChanged.isEmpty()) {
      EnquiryDuplicateService.flagDuplicates(contactChanged);
    }
    for (Lead enquiry : (List<Lead>) newRecords) {
      Lead previous = (Lead) oldMap.get(enquiry.Id);
      if (enquiry.Status == 'Contacted' && previous.Status != 'Contacted') {
        enquiry.Last_Contacted__c = System.now();
      }
    }
  }

  protected override void afterInsert(List<SObject> newRecords) {
    ReferralService.recordReferrals((List<Lead>) newRecords);
    List<Task> tasks = new List<Task>();
    for (Lead enquiry : (List<Lead>) newRecords) {
      if (
        enquiry.Branch__c != null &&
        enquiry.OwnerId != null &&
        enquiry.OwnerId.getSObjectType() == User.SObjectType
      ) {
        tasks.add(
          new Task(
            Subject = 'First contact: ' +
              enquiry.FirstName +
              ' ' +
              enquiry.LastName,
            WhoId = enquiry.Id,
            OwnerId = enquiry.OwnerId,
            ActivityDate = enquiry.Next_Follow_Up__c.date(),
            Priority = 'High',
            Status = 'Not Started',
            Description = 'Contact the enquirer within ' +
              FIRST_CONTACT_HOURS +
              ' hours of the enquiry.'
          )
        );
      }
    }
    if (!tasks.isEmpty()) {
      Logger.errors(
        'LeadTriggerHandler.afterInsert',
        Database.insert(tasks, false, AccessLevel.SYSTEM_MODE)
      );
    }
  }
}
