/** Normalises subject codes and enforces branch + curriculum + code uniqueness. */
public inherited sharing class SubjectTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    stamp((List<Subject__c>) newRecords);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<Subject__c>) newRecords);
  }

  private static void stamp(List<Subject__c> subjects) {
    Set<Id> branchIds = new Set<Id>();
    for (Subject__c subject : subjects) {
      if (subject.Branch__c != null) {
        branchIds.add(subject.Branch__c);
      }
    }
    Map<Id, LearningCourse> branches = branchIds.isEmpty()
      ? new Map<Id, LearningCourse>()
      : new Map<Id, LearningCourse>(
          [
            SELECT
              Id,
              Programme__r.Duration_Years__c,
              Programme__r.Terms_Per_Year__c
            FROM LearningCourse
            WHERE Id IN :branchIds
            WITH SYSTEM_MODE
          ]
        );
    for (Subject__c subject : subjects) {
      LearningCourse branch = branches.get(subject.Branch__c);
      if (
        branch?.Programme__r?.Duration_Years__c != null &&
        subject.Year_Of_Study__c != null &&
        subject.Year_Of_Study__c > branch.Programme__r.Duration_Years__c
      ) {
        subject.Year_Of_Study__c.addError(
          'Subject year of study cannot exceed the programme duration.'
        );
      }
      if (
        branch?.Programme__r?.Duration_Years__c != null &&
        branch.Programme__r.Terms_Per_Year__c != null &&
        subject.Term__c != null &&
        subject.Term__c >
        branch.Programme__r.Duration_Years__c *
        branch.Programme__r.Terms_Per_Year__c
      ) {
        subject.Term__c.addError(
          'Subject term cannot exceed the programme term count.'
        );
      }
      subject.Subject_Code__c = String.isBlank(subject.Subject_Code__c)
        ? null
        : subject.Subject_Code__c.trim().toUpperCase();
      subject.Curriculum_Version__c = String.isBlank(
          subject.Curriculum_Version__c
        )
        ? null
        : subject.Curriculum_Version__c.trim();
      subject.Unique_Key__c = subject.Branch__c == null ||
        subject.Curriculum_Version__c == null ||
        subject.Subject_Code__c == null
        ? null
        : String.valueOf(subject.Branch__c) +
          '|' +
          subject.Curriculum_Version__c +
          '|' +
          subject.Subject_Code__c;
    }
  }
}
