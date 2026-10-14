/** Universal data-integrity guards for college programme enrolments. */
public without sharing class ProgrammeEnrolmentTriggerHandler {
  public static void beforeInsert(List<Programme_Enrolment__c> values) {
    for (Programme_Enrolment__c value : values) {
      if (value.Status__c != 'Provisional') {
        value.addError('A programme enrolment must start as Provisional.');
      }
      populateKeys(value);
    }
  }

  public static void beforeUpdate(
    List<Programme_Enrolment__c> values,
    Map<Id, Programme_Enrolment__c> oldById
  ) {
    for (Programme_Enrolment__c value : values) {
      Programme_Enrolment__c oldValue = oldById.get(value.Id);
      if (
        value.Application__c != oldValue.Application__c ||
        value.Student__c != oldValue.Student__c ||
        value.Programme__c != oldValue.Programme__c
      ) {
        value.addError(
          'Application, student and programme cannot be changed after creation.'
        );
      }
      if (
        String.isNotBlank(oldValue.Roll_Number__c) &&
        value.Roll_Number__c != oldValue.Roll_Number__c
      ) {
        value.addError('A roll number cannot be changed or reused.');
      }
      if (
        value.Status__c != oldValue.Status__c &&
        !canTransition(oldValue.Status__c, value.Status__c)
      ) {
        value.addError(
          'Programme enrolment cannot move from ' +
            oldValue.Status__c +
            ' to ' +
            value.Status__c +
            '.'
        );
      }
      if (
        value.Status__c == 'Completed' &&
        oldValue.Status__c != 'Completed' &&
        value.Completed_On__c == null
      ) {
        value.Completed_On__c = Date.today();
      }
      if (
        value.Status__c == 'Discontinued' &&
        oldValue.Status__c != 'Discontinued' &&
        value.Discontinued_On__c == null
      ) {
        value.Discontinued_On__c = Date.today();
      }
      populateKeys(value);
    }
  }

  private static Boolean canTransition(String source, String target) {
    if (source == 'Provisional')
      return new Set<String>{ 'Enrolled', 'Expired', 'Cancelled' }
        .contains(target);
    if (source == 'Enrolled')
      return new Set<String>{ 'Completed', 'Discontinued' }.contains(target);
    return false;
  }

  private static void populateKeys(Programme_Enrolment__c value) {
    value.Application_Key__c = value.Application__c == null
      ? null
      : String.valueOf(value.Application__c);
    value.Active_Key__c = (value.Status__c == 'Provisional' ||
      value.Status__c == 'Enrolled') &&
      value.Student__c != null &&
      value.Programme__c != null
      ? String.valueOf(value.Student__c) +
        '|' +
        String.valueOf(value.Programme__c)
      : null;
  }
}
