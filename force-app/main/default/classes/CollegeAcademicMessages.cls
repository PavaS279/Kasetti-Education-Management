/** Student and parent notices for published and reopened college results. Never blocks the result transaction. */
public without sharing class CollegeAcademicMessages {
  public static void resultsPublished(Set<Id> termResultIds) {
    if (termResultIds == null || termResultIds.isEmpty()) {
      return;
    }
    try {
      List<MessageService.Notice> notices = new List<MessageService.Notice>();
      List<Term_Result__c> rows = [
        SELECT
          Id,
          Term__c,
          Outcome__c,
          Percentage__c,
          Backlogs__c,
          Student__c,
          Student__r.PersonContactId,
          Student__r.Name,
          Programme_Enrolment__r.Campus__c,
          Programme_Enrolment__r.Roll_Number__c
        FROM Term_Result__c
        WHERE Id IN :termResultIds
        WITH SYSTEM_MODE
      ];
      for (Term_Result__c t : rows) {
        Map<String, String> values = new Map<String, String>{
          'StudentName' => t.Student__r.Name,
          'RollNumber' => t.Programme_Enrolment__r.Roll_Number__c,
          'Term' => String.valueOf(t.Term__c.intValue()),
          'Outcome' => t.Outcome__c,
          'Percentage' => String.valueOf(t.Percentage__c),
          'Backlogs' => String.valueOf(t.Backlogs__c.intValue()),
          'Reason' => ''
        };
        notices.addAll(
          noticesFor(
            t.Student__c,
            t.Student__r.PersonContactId,
            t.Programme_Enrolment__r.Campus__c,
            t.Id,
            values
          )
        );
      }
      MessageService.notify('College_Results_Published', notices);
    } catch (Exception failure) {
      Logger.error('CollegeAcademicMessages.resultsPublished', failure, null);
    }
  }

  public static void resultsReopened(Set<Id> subjectResultIds, String reason) {
    try {
      List<MessageService.Notice> notices = new List<MessageService.Notice>();
      for (Subject_Result__c r : [
        SELECT
          Id,
          Term__c,
          Reopen_Count__c,
          Student__c,
          Student__r.PersonContactId,
          Student__r.Name,
          Section_Subject__r.Subject__r.Name,
          Programme_Enrolment__r.Campus__c,
          Programme_Enrolment__r.Roll_Number__c
        FROM Subject_Result__c
        WHERE Id IN :subjectResultIds
        WITH SYSTEM_MODE
      ]) {
        Map<String, String> values = new Map<String, String>{
          'StudentName' => r.Student__r.Name,
          'RollNumber' => r.Programme_Enrolment__r.Roll_Number__c,
          'Term' => String.valueOf(r.Term__c.intValue()),
          'SubjectName' => r.Section_Subject__r.Subject__r.Name,
          'Reason' => reason
        };
        List<MessageService.Notice> forStudent = noticesFor(
          r.Student__c,
          r.Student__r.PersonContactId,
          r.Programme_Enrolment__r.Campus__c,
          r.Id,
          values
        );
        for (MessageService.Notice n : forStudent) {
          n.dedupSuffix = String.valueOf(r.Reopen_Count__c);
        }
        notices.addAll(forStudent);
      }
      MessageService.notify('College_Result_Reopened', notices);
    } catch (Exception failure) {
      Logger.error('CollegeAcademicMessages.resultsReopened', failure, null);
    }
  }

  private static List<MessageService.Notice> noticesFor(
    Id studentId,
    Id studentContactId,
    Id campusId,
    Id relatedId,
    Map<String, String> values
  ) {
    Set<Id> recipients = new Set<Id>{ studentContactId };
    Id payer = MessageService.feePayersOf(new Set<Id>{ studentContactId })
      .get(studentContactId);
    if (payer != null) {
      recipients.add(payer);
    }
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    for (Id recipientId : recipients) {
      MessageService.Notice notice = new MessageService.Notice();
      notice.recipientId = recipientId;
      notice.learnerContactId = studentContactId;
      notice.learnerAccountId = studentId;
      notice.branchId = campusId;
      notice.relatedId = relatedId;
      for (String key : values.keySet()) {
        notice.values.put(key, values.get(key) == null ? '' : values.get(key));
      }
      notices.add(notice);
    }
    return notices;
  }
}
