/**
 * Routes the standard New buttons (Branch, Room, Course, Class, Account) to
 * the KTEdutech guided screens (Phase 5 stage 6). Staff go straight to the
 * guided screen; administrators choose between it and the standard form,
 * which stays available as a fallback. Business accounts and people who
 * cannot complete a guided screen get the standard form.
 */
public with sharing class NewRouterController {
  public class Context {
    @AuraEnabled
    public String objectLabel;
    /** branch | room | course | class | family, or null for the standard form. */
    @AuraEnabled
    public String wizard;
    @AuraEnabled
    public Boolean isAdministrator = false;
  }

  @AuraEnabled
  public static Context getContext(String objectApiName, Id recordTypeId) {
    try {
      Context c = new Context();
      Schema.SObjectType type = Schema.getGlobalDescribe().get(objectApiName);
      if (type == null) {
        throw new AppException('Unknown object ' + objectApiName + '.');
      }
      // KTEdutech names for Education Cloud objects.
      Map<String, String> names = new Map<String, String>{
        'LearningCourse' => 'Course',
        'CourseOffering' => 'Class'
      };
      c.objectLabel = names.containsKey(objectApiName)
        ? names.get(objectApiName)
        : type.getDescribe().getLabel();
      c.wizard = wizardFor(objectApiName, recordTypeId);
      c.isAdministrator = isAdministrator();
      return c;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @TestVisible
  private static String wizardFor(String objectApiName, Id recordTypeId) {
    switch on objectApiName {
      when 'Branch__c' {
        return Schema.SObjectType.Branch__c.isCreateable() ? 'branch' : null;
      }
      when 'Room__c' {
        return Schema.SObjectType.Room__c.isCreateable() ? 'room' : null;
      }
      when 'LearningCourse' {
        return Schema.SObjectType.LearningCourse.isCreateable() &&
          Schema.SObjectType.Learning.isCreateable()
          ? 'course'
          : null;
      }
      when 'CourseOffering' {
        return Schema.SObjectType.CourseOffering.isCreateable() &&
          Schema.SObjectType.CourseOfferingSchedule.isCreateable() &&
          Schema.SObjectType.LearningCourse.isAccessible()
          ? 'class'
          : null;
      }
      when 'Account' {
        Boolean person =
          recordTypeId == null ||
          recordTypeId == PersonAccountService.personRecordTypeId();
        Boolean canAddFamilies =
          Schema.SObjectType.Account.isCreateable() &&
          (Schema.SObjectType.IndividualApplication.isCreateable() ||
          Schema.SObjectType.CourseOfferingParticipant.isCreateable());
        return person && canAddFamilies ? 'family' : null;
      }
      when else {
        return null;
      }
    }
  }

  /** System Administrators (Modify All Data) and the KEM Administrator persona. */
  @TestVisible
  private static Boolean isAdministrator() {
    return [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND (PermissionSet.PermissionsModifyAllData = TRUE
          OR PermissionSet.Name = 'KEM_Administrator'
          OR PermissionSetGroup.DeveloperName = 'KEM_Administrator_Persona')
        WITH SYSTEM_MODE
      ] > 0;
  }
}
