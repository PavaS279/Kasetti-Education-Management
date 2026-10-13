/** Freezes subject defaults on a section-subject assignment and maintains its key. */
public inherited sharing class SectionSubjectTriggerHandler extends TriggerHandler {
  protected override void beforeInsert(List<SObject> newRecords) {
    stamp((List<Section_Subject__c>) newRecords, null);
  }

  protected override void beforeUpdate(
    List<SObject> newRecords,
    Map<Id, SObject> oldMap
  ) {
    stamp((List<Section_Subject__c>) newRecords, oldMap);
  }

  private static void stamp(
    List<Section_Subject__c> rows,
    Map<Id, SObject> oldMap
  ) {
    Set<Id> subjectIds = new Set<Id>();
    Set<Id> sectionIds = new Set<Id>();
    Set<Id> roomIds = new Set<Id>();
    for (Section_Subject__c row : rows) {
      if (row.Subject__c != null) {
        subjectIds.add(row.Subject__c);
      }
      if (row.Section__c != null) {
        sectionIds.add(row.Section__c);
      }
      if (row.Default_Room__c != null) {
        roomIds.add(row.Default_Room__c);
      }
    }
    Map<Id, Subject__c> subjects = subjectIds.isEmpty()
      ? new Map<Id, Subject__c>()
      : new Map<Id, Subject__c>(
          [
            SELECT
              Id,
              Branch__c,
              Year_Of_Study__c,
              Term__c,
              Credits__c,
              Internal_Max__c,
              Exam_Max__c,
              Internal_Pass_Percent__c,
              Exam_Pass_Percent__c,
              Total_Pass_Percent__c
            FROM Subject__c
            WHERE Id IN :subjectIds
            WITH SYSTEM_MODE
          ]
        );
    Map<Id, CourseOffering> sections = sectionIds.isEmpty()
      ? new Map<Id, CourseOffering>()
      : new Map<Id, CourseOffering>(
          [
            SELECT Id, LearningCourseId, Year_Of_Study__c, Branch__c
            FROM CourseOffering
            WHERE Id IN :sectionIds
            WITH SYSTEM_MODE
          ]
        );
    Map<Id, Room__c> rooms = roomIds.isEmpty()
      ? new Map<Id, Room__c>()
      : new Map<Id, Room__c>(
          [
            SELECT Id, Branch__c
            FROM Room__c
            WHERE Id IN :roomIds
            WITH SYSTEM_MODE
          ]
        );
    for (Section_Subject__c row : rows) {
      Subject__c subject = subjects.get(row.Subject__c);
      CourseOffering section = sections.get(row.Section__c);
      Room__c room = rooms.get(row.Default_Room__c);
      if (
        subject != null &&
        section != null &&
        subject.Branch__c != section.LearningCourseId
      ) {
        row.Subject__c.addError(
          'Select a subject from the same college branch as the section.'
        );
      }
      if (
        room != null &&
        section != null &&
        room.Branch__c != section.Branch__c
      ) {
        row.Default_Room__c.addError(
          'Select a room from the same campus as the section.'
        );
      }
      if (
        subject != null &&
        section != null &&
        subject.Year_Of_Study__c != section.Year_Of_Study__c
      ) {
        row.Subject__c.addError(
          'Select a subject for the section\'s year of study.'
        );
      }
      if (subject != null) {
        if (row.Term__c == null) {
          row.Term__c = subject.Term__c;
        } else if (row.Term__c != subject.Term__c) {
          row.Term__c.addError(
            'The section subject term must match the catalogue subject term.'
          );
        }
        row.Credits__c = row.Credits__c == null
          ? subject.Credits__c
          : row.Credits__c;
        row.Internal_Max__c = row.Internal_Max__c == null
          ? subject.Internal_Max__c
          : row.Internal_Max__c;
        row.Exam_Max__c = row.Exam_Max__c == null
          ? subject.Exam_Max__c
          : row.Exam_Max__c;
        row.Internal_Pass_Percent__c = row.Internal_Pass_Percent__c == null
          ? subject.Internal_Pass_Percent__c
          : row.Internal_Pass_Percent__c;
        row.Exam_Pass_Percent__c = row.Exam_Pass_Percent__c == null
          ? subject.Exam_Pass_Percent__c
          : row.Exam_Pass_Percent__c;
        row.Total_Pass_Percent__c = row.Total_Pass_Percent__c == null
          ? subject.Total_Pass_Percent__c
          : row.Total_Pass_Percent__c;
      }
      row.Unique_Key__c = row.Section__c == null ||
        row.Subject__c == null ||
        row.Term__c == null
        ? null
        : String.valueOf(row.Section__c) +
          '|' +
          String.valueOf(row.Subject__c) +
          '|' +
          String.valueOf(row.Term__c.intValue());
    }
  }
}
