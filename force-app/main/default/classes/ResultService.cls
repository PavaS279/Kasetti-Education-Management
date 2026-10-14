/**
 * College results: section enrolment -> section subject -> subject result ->
 * assessment results, with term results above them. Subject results are
 * calculated from published Internal and Exam assessments of the section
 * subject, finalised by the Dean (locked and published to the portal) and
 * reopened only by the Dean with a reason.
 */
public without sharing class ResultService {
  public static final String FINALISE_PERMISSION = 'KEM_Finalise_Results';
  public static final String REOPEN_PERMISSION = 'KEM_Reopen_Results';
  public static final String FINAL_STATUS = 'Final';
  public static final String RESULTS_FINAL = 'Results Final';

  /** Set only inside this service so the lock triggers let its own writes through. */
  @TestVisible
  private static Boolean unlocked = false;

  public static Boolean isUnlocked() {
    return unlocked;
  }

  // ------------------------------------------------------------ draft results

  /** Creates the first-attempt Draft subject result for every section subject of each section enrolment. Idempotent. */
  public static void ensureResults(Set<Id> sectionEnrolmentIds) {
    List<CourseOfferingParticipant> enrolments = [
      SELECT Id, CourseOfferingId, ParticipantAccountId, Programme_Enrolment__c
      FROM CourseOfferingParticipant
      WHERE Id IN :sectionEnrolmentIds AND Programme_Enrolment__c != NULL
      WITH SYSTEM_MODE
    ];
    Set<Id> sectionIds = new Set<Id>();
    for (CourseOfferingParticipant e : enrolments) {
      sectionIds.add(e.CourseOfferingId);
    }
    Map<Id, List<Section_Subject__c>> subjectsBySection = new Map<Id, List<Section_Subject__c>>();
    for (Section_Subject__c s : [
      SELECT Id, Section__c, Term__c, Internal_Max__c, Exam_Max__c
      FROM Section_Subject__c
      WHERE Section__c IN :sectionIds
      WITH SYSTEM_MODE
    ]) {
      if (!subjectsBySection.containsKey(s.Section__c)) {
        subjectsBySection.put(s.Section__c, new List<Section_Subject__c>());
      }
      subjectsBySection.get(s.Section__c).add(s);
    }
    List<Subject_Result__c> rows = new List<Subject_Result__c>();
    for (CourseOfferingParticipant e : enrolments) {
      if (!subjectsBySection.containsKey(e.CourseOfferingId)) {
        continue;
      }
      for (Section_Subject__c s : subjectsBySection.get(e.CourseOfferingId)) {
        rows.add(draft(e, s, 1));
      }
    }
    upsertResults(rows);
  }

  private static Subject_Result__c draft(
    CourseOfferingParticipant e,
    Section_Subject__c s,
    Integer attempt
  ) {
    return new Subject_Result__c(
      Unique_Key__c = key(e.Id, s.Id, attempt),
      Section_Enrolment__c = e.Id,
      Section_Subject__c = s.Id,
      Programme_Enrolment__c = e.Programme_Enrolment__c,
      Student__c = e.ParticipantAccountId,
      Term__c = s.Term__c,
      Attempt__c = attempt,
      Max_Marks__c = nvl(s.Internal_Max__c) + nvl(s.Exam_Max__c),
      Status__c = 'Draft',
      Result__c = 'Pending',
      Reopen_Count__c = 0
    );
  }

  /** A re-attempt (attempt n+1) of a failed subject, registered on the student's current section enrolment. */
  public static Id registerReattempt(
    Id failedResultId,
    Id currentSectionEnrolmentId
  ) {
    Subject_Result__c failed = [
      SELECT
        Id,
        Section_Subject__c,
        Attempt__c,
        Result__c,
        Status__c,
        Section_Subject__r.Id,
        Section_Subject__r.Term__c,
        Section_Subject__r.Internal_Max__c,
        Section_Subject__r.Exam_Max__c,
        Internal_Marks__c
      FROM Subject_Result__c
      WHERE Id = :failedResultId
      WITH SYSTEM_MODE
    ];
    if (failed.Status__c != FINAL_STATUS || failed.Result__c == 'Pass') {
      throw new AppException(
        'Only a final failed subject result can be re-attempted.'
      );
    }
    CourseOfferingParticipant current = [
      SELECT Id, ParticipantAccountId, Programme_Enrolment__c
      FROM CourseOfferingParticipant
      WHERE Id = :currentSectionEnrolmentId
      WITH SYSTEM_MODE
    ];
    Integer attempt = failed.Attempt__c.intValue() + 1;
    Subject_Result__c row = draft(current, failed.Section_Subject__r, attempt);
    row.Section_Subject__c = failed.Section_Subject__c;
    row.Term__c = failed.Section_Subject__r.Term__c;
    // Internal marks carry over to a re-attempt; only the exam is taken again.
    row.Internal_Marks__c = failed.Internal_Marks__c;
    upsertResults(new List<Subject_Result__c>{ row });
    // The subject takes marks again for the re-exam until the Dean finalises it.
    markSubject(
      failed.Section_Subject__c,
      openStatus(
        [
          SELECT Id, Default_Room__c
          FROM Section_Subject__c
          WHERE Id = :failed.Section_Subject__c
          WITH SYSTEM_MODE
        ]
      )
    );
    return [
      SELECT Id
      FROM Subject_Result__c
      WHERE Unique_Key__c = :row.Unique_Key__c
      WITH SYSTEM_MODE
    ]
    .Id;
  }

  // ------------------------------------------------------------ calculation

  /** Recalculates the Draft and Reopened subject results of the section subjects. */
  public static void recalculate(Set<Id> sectionSubjectIds) {
    sectionSubjectIds.remove(null);
    if (sectionSubjectIds.isEmpty()) {
      return;
    }
    Map<Id, Section_Subject__c> subjects = new Map<Id, Section_Subject__c>(
      [
        SELECT
          Id,
          Internal_Max__c,
          Exam_Max__c,
          Internal_Pass_Percent__c,
          Exam_Pass_Percent__c,
          Total_Pass_Percent__c
        FROM Section_Subject__c
        WHERE Id IN :sectionSubjectIds
        WITH SYSTEM_MODE
      ]
    );
    List<Subject_Result__c> results = [
      SELECT
        Id,
        Section_Subject__c,
        Student__c,
        Attempt__c,
        Internal_Marks__c,
        Status__c,
        Section_Enrolment__r.ParticipantContactId
      FROM Subject_Result__c
      WHERE
        Section_Subject__c IN :sectionSubjectIds
        AND Status__c != :FINAL_STATUS
      WITH SYSTEM_MODE
    ];
    if (results.isEmpty()) {
      return;
    }
    // Earliest finalisation of an earlier attempt: re-attempt exams count only after it.
    Map<String, Datetime> previousAttemptEnd = new Map<String, Datetime>();
    for (Subject_Result__c prior : [
      SELECT Section_Subject__c, Student__c, Attempt__c, Finalised_On__c
      FROM Subject_Result__c
      WHERE
        Section_Subject__c IN :sectionSubjectIds
        AND Status__c = :FINAL_STATUS
      WITH SYSTEM_MODE
    ]) {
      String k =
        prior.Section_Subject__c +
        '|' +
        prior.Student__c +
        '|' +
        (prior.Attempt__c.intValue() + 1);
      previousAttemptEnd.put(k, prior.Finalised_On__c);
    }
    Map<String, List<Assessment_Result__c>> marks = new Map<String, List<Assessment_Result__c>>();
    for (Assessment_Result__c r : [
      SELECT
        Id,
        Learner__c,
        Score__c,
        Max_Score__c,
        Absent__c,
        Subject_Result__c,
        Course_Assessment__r.Section_Subject__c,
        Course_Assessment__r.Component__c,
        Course_Assessment__r.Weight__c,
        Course_Assessment__r.CreatedDate
      FROM Assessment_Result__c
      WHERE
        Course_Assessment__r.Section_Subject__c IN :sectionSubjectIds
        AND Course_Assessment__r.Status__c = 'Published'
        AND Status__c = 'Published'
      WITH SYSTEM_MODE
    ]) {
      String k = r.Course_Assessment__r.Section_Subject__c + '|' + r.Learner__c;
      if (!marks.containsKey(k)) {
        marks.put(k, new List<Assessment_Result__c>());
      }
      marks.get(k).add(r);
    }
    List<Assessment_Result__c> links = new List<Assessment_Result__c>();
    for (Subject_Result__c result : results) {
      Section_Subject__c s = subjects.get(result.Section_Subject__c);
      Datetime after = previousAttemptEnd.get(
        result.Section_Subject__c +
          '|' +
          result.Student__c +
          '|' +
          result.Attempt__c.intValue()
      );
      Component internal = new Component();
      Component exam = new Component();
      List<Assessment_Result__c> rows = marks.get(
        result.Section_Subject__c +
          '|' +
          result.Section_Enrolment__r.ParticipantContactId
      );
      for (
        Assessment_Result__c r : rows == null
          ? new List<Assessment_Result__c>()
          : rows
      ) {
        Boolean isExam = r.Course_Assessment__r.Component__c == 'Exam';
        if (
          after != null &&
          (!isExam || r.Course_Assessment__r.CreatedDate <= after)
        ) {
          continue; // a re-attempt keeps its internal marks and counts only the new exam
        }
        (isExam ? exam : internal).add(r);
        if (r.Subject_Result__c != result.Id) {
          links.add(
            new Assessment_Result__c(Id = r.Id, Subject_Result__c = result.Id)
          );
        }
      }
      Decimal internalMarks = after != null
        ? nvl(result.Internal_Marks__c)
        : internal.scaled(s.Internal_Max__c);
      Decimal examMarks = exam.scaled(s.Exam_Max__c);
      Decimal maxMarks = nvl(s.Internal_Max__c) + nvl(s.Exam_Max__c);
      result.Internal_Marks__c = internalMarks;
      result.Exam_Marks__c = examMarks;
      result.Max_Marks__c = maxMarks;
      result.Total_Marks__c = internalMarks + examMarks;
      result.Percentage__c = maxMarks == 0
        ? 0
        : (result.Total_Marks__c * 100 / maxMarks).setScale(2);
      if (exam.count == 0 && nvl(s.Exam_Max__c) > 0) {
        result.Result__c = 'Pending';
      } else if (exam.count > 0 && exam.allAbsent()) {
        result.Result__c = 'Absent';
      } else {
        Boolean pass =
          meets(internalMarks, s.Internal_Max__c, s.Internal_Pass_Percent__c) &&
          meets(examMarks, s.Exam_Max__c, s.Exam_Pass_Percent__c) &&
          meets(result.Total_Marks__c, maxMarks, s.Total_Pass_Percent__c);
        result.Result__c = pass ? 'Pass' : 'Fail';
      }
    }
    unlocked = true;
    try {
      Database.update(results, AccessLevel.SYSTEM_MODE);
      if (!links.isEmpty()) {
        Database.update(links, AccessLevel.SYSTEM_MODE);
      }
    } finally {
      unlocked = false;
    }
  }

  private class Component {
    Decimal weighted = 0;
    Decimal weights = 0;
    Integer count = 0;
    Integer absent = 0;

    void add(Assessment_Result__c r) {
      count++;
      Decimal w = r.Course_Assessment__r.Weight__c == null ||
        r.Course_Assessment__r.Weight__c <= 0
        ? 1
        : r.Course_Assessment__r.Weight__c;
      weights += w;
      if (r.Absent__c == true) {
        absent++;
        return;
      }
      if (r.Max_Score__c != null && r.Max_Score__c > 0) {
        weighted += w * nvl(r.Score__c) / r.Max_Score__c;
      }
    }

    Decimal scaled(Decimal componentMax) {
      if (weights == 0) {
        return 0;
      }
      return (weighted / weights * nvl(componentMax)).setScale(2);
    }

    Boolean allAbsent() {
      return count > 0 && absent == count;
    }
  }

  private static Boolean meets(
    Decimal marks,
    Decimal max,
    Decimal passPercent
  ) {
    if (passPercent == null || max == null || max == 0) {
      return true;
    }
    return marks * 100 / max >= passPercent;
  }

  // ------------------------------------------------------------ finalise / reopen

  /** Dean finalises a section subject: results recalculated, locked and published; term results follow. */
  public static Integer finalise(Id sectionSubjectId) {
    RecordAccess.assertPermission(FINALISE_PERMISSION);
    Section_Subject__c subject = [
      SELECT Id, Section__c, Term__c, Status__c
      FROM Section_Subject__c
      WHERE Id = :sectionSubjectId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    recalculate(new Set<Id>{ sectionSubjectId });
    List<Subject_Result__c> open = [
      SELECT Id, Result__c, Section_Enrolment__c, Student__r.Name
      FROM Subject_Result__c
      WHERE
        Section_Subject__c = :sectionSubjectId
        AND Status__c != :FINAL_STATUS
      WITH SYSTEM_MODE
    ];
    if (open.isEmpty()) {
      if (subject.Status__c != RESULTS_FINAL) {
        markSubject(subject.Id, RESULTS_FINAL);
      }
      return 0;
    }
    for (Subject_Result__c r : open) {
      if (r.Result__c == 'Pending') {
        throw new AppException(
          'Publish the exam marks for ' +
            r.Student__r.Name +
            ' before finalising.'
        );
      }
      r.Status__c = FINAL_STATUS;
      r.Finalised_By__c = UserInfo.getUserId();
      r.Finalised_On__c = System.now();
    }
    unlocked = true;
    try {
      Database.update(open, AccessLevel.SYSTEM_MODE);
    } finally {
      unlocked = false;
    }
    markSubject(subject.Id, RESULTS_FINAL);
    Set<Id> enrolmentIds = new Set<Id>();
    for (Subject_Result__c r : open) {
      enrolmentIds.add(r.Section_Enrolment__c);
    }
    Set<Id> finalTerms = finaliseTerms(
      enrolmentIds,
      subject.Term__c.intValue()
    );
    CollegeAcademicMessages.resultsPublished(finalTerms);
    return open.size();
  }

  /** Dean reopens final subject results with a reason; the term result is hidden again until re-finalised. */
  public static void reopen(Set<Id> subjectResultIds, String reason) {
    RecordAccess.assertPermission(REOPEN_PERMISSION);
    if (String.isBlank(reason)) {
      throw new AppException('Enter the reason for reopening the results.');
    }
    List<Subject_Result__c> rows = [
      SELECT
        Id,
        Status__c,
        Reopen_Count__c,
        Section_Subject__c,
        Section_Enrolment__c,
        Term__c
      FROM Subject_Result__c
      WHERE Id IN :subjectResultIds
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Set<Id> subjects = new Set<Id>();
    Set<String> termKeys = new Set<String>();
    List<Subject_Result__c> changed = new List<Subject_Result__c>();
    for (Subject_Result__c r : rows) {
      if (r.Status__c != FINAL_STATUS) {
        continue;
      }
      r.Status__c = 'Reopened';
      r.Reopen_Reason__c = reason.trim().left(255);
      r.Reopened_By__c = UserInfo.getUserId();
      r.Reopened_On__c = System.now();
      r.Reopen_Count__c = nvl(r.Reopen_Count__c) + 1;
      changed.add(r);
      subjects.add(r.Section_Subject__c);
      termKeys.add(termKey(r.Section_Enrolment__c, r.Term__c.intValue()));
    }
    if (changed.isEmpty()) {
      return;
    }
    List<Term_Result__c> terms = [
      SELECT Id, Status__c
      FROM Term_Result__c
      WHERE Unique_Key__c IN :termKeys AND Status__c = :FINAL_STATUS
      WITH SYSTEM_MODE
    ];
    for (Term_Result__c t : terms) {
      t.Status__c = 'Reopened';
    }
    List<Section_Subject__c> subjectRows = new List<Section_Subject__c>();
    for (Section_Subject__c s : [
      SELECT Id, Default_Room__c
      FROM Section_Subject__c
      WHERE Id IN :subjects
      WITH SYSTEM_MODE
    ]) {
      subjectRows.add(
        new Section_Subject__c(Id = s.Id, Status__c = openStatus(s))
      );
    }
    unlocked = true;
    try {
      Database.update(changed, AccessLevel.SYSTEM_MODE);
      Database.update(terms, AccessLevel.SYSTEM_MODE);
      Database.update(subjectRows, AccessLevel.SYSTEM_MODE);
    } finally {
      unlocked = false;
    }
    CollegeAcademicMessages.resultsReopened(
      new Map<Id, Subject_Result__c>(changed).keySet(),
      reason.trim()
    );
  }

  /** Term results for the term once every section subject of that term is final. Returns the final term result ids. */
  private static Set<Id> finaliseTerms(
    Set<Id> sectionEnrolmentIds,
    Integer term
  ) {
    Map<Id, CourseOfferingParticipant> enrolments = new Map<Id, CourseOfferingParticipant>(
      [
        SELECT
          Id,
          CourseOfferingId,
          ParticipantAccountId,
          Programme_Enrolment__c,
          Programme_Enrolment__r.Programme__r.Max_Backlogs_For_Promotion__c
        FROM CourseOfferingParticipant
        WHERE Id IN :sectionEnrolmentIds
        WITH SYSTEM_MODE
      ]
    );
    Set<Id> sectionIds = new Set<Id>();
    for (CourseOfferingParticipant e : enrolments.values()) {
      sectionIds.add(e.CourseOfferingId);
    }
    Set<Id> sectionsStillOpen = new Set<Id>();
    for (Section_Subject__c s : [
      SELECT Section__c
      FROM Section_Subject__c
      WHERE
        Section__c IN :sectionIds
        AND Term__c = :term
        AND Status__c != :RESULTS_FINAL
      WITH SYSTEM_MODE
    ]) {
      sectionsStillOpen.add(s.Section__c);
    }
    Map<Id, List<Subject_Result__c>> byEnrolment = new Map<Id, List<Subject_Result__c>>();
    for (Subject_Result__c r : [
      SELECT
        Id,
        Section_Enrolment__c,
        Result__c,
        Total_Marks__c,
        Max_Marks__c,
        Status__c
      FROM Subject_Result__c
      WHERE Section_Enrolment__c IN :sectionEnrolmentIds AND Term__c = :term
      WITH SYSTEM_MODE
    ]) {
      if (!byEnrolment.containsKey(r.Section_Enrolment__c)) {
        byEnrolment.put(r.Section_Enrolment__c, new List<Subject_Result__c>());
      }
      byEnrolment.get(r.Section_Enrolment__c).add(r);
    }
    List<Term_Result__c> terms = new List<Term_Result__c>();
    for (CourseOfferingParticipant e : enrolments.values()) {
      if (
        sectionsStillOpen.contains(e.CourseOfferingId) ||
        !byEnrolment.containsKey(e.Id)
      ) {
        continue;
      }
      Integer passed = 0;
      Integer failed = 0;
      Decimal total = 0;
      Decimal max = 0;
      Boolean allFinal = true;
      for (Subject_Result__c r : byEnrolment.get(e.Id)) {
        allFinal &= r.Status__c == FINAL_STATUS;
        if (r.Result__c == 'Pass') {
          passed++;
        } else {
          failed++;
        }
        total += nvl(r.Total_Marks__c);
        max += nvl(r.Max_Marks__c);
      }
      if (!allFinal) {
        continue;
      }
      Decimal allowed = nvl(
        e.Programme_Enrolment__r.Programme__r.Max_Backlogs_For_Promotion__c
      );
      terms.add(
        new Term_Result__c(
          Unique_Key__c = termKey(e.Id, term),
          Section_Enrolment__c = e.Id,
          Programme_Enrolment__c = e.Programme_Enrolment__c,
          Student__c = e.ParticipantAccountId,
          Term__c = term,
          Status__c = FINAL_STATUS,
          Outcome__c = failed == 0
            ? 'Pass'
            : (failed <= allowed ? 'Pass with backlog' : 'Fail'),
          Subjects_Passed__c = passed,
          Backlogs__c = failed,
          Total_Marks__c = total,
          Max_Marks__c = max,
          Percentage__c = max == 0 ? 0 : (total * 100 / max).setScale(2),
          Finalised_On__c = System.now()
        )
      );
    }
    if (terms.isEmpty()) {
      return new Set<Id>();
    }
    unlocked = true;
    try {
      Database.upsert(
        terms,
        Term_Result__c.Unique_Key__c,
        AccessLevel.SYSTEM_MODE
      );
    } finally {
      unlocked = false;
    }
    return new Map<Id, Term_Result__c>(terms).keySet();
  }

  /** Active needs a room (validation rule); without one the subject goes back to Planned. */
  private static String openStatus(Section_Subject__c subject) {
    return subject.Default_Room__c == null ? 'Planned' : 'Active';
  }

  private static void markSubject(Id sectionSubjectId, String status) {
    Database.update(
      new Section_Subject__c(Id = sectionSubjectId, Status__c = status),
      AccessLevel.SYSTEM_MODE
    );
  }

  // ------------------------------------------------------------ reads

  /** Open backlogs of a programme enrolment: failed final results without a later passing attempt. */
  public static List<Subject_Result__c> openBacklogs(Id programmeEnrolmentId) {
    Map<Id, Subject_Result__c> latest = new Map<Id, Subject_Result__c>();
    for (Subject_Result__c r : [
      SELECT
        Id,
        Section_Subject__c,
        Attempt__c,
        Result__c,
        Status__c,
        Section_Subject__r.Subject__r.Name
      FROM Subject_Result__c
      WHERE
        Programme_Enrolment__c = :programmeEnrolmentId
        AND Status__c = :FINAL_STATUS
      WITH SYSTEM_MODE
      ORDER BY Attempt__c ASC
    ]) {
      latest.put(r.Section_Subject__c, r);
    }
    List<Subject_Result__c> open = new List<Subject_Result__c>();
    for (Subject_Result__c r : latest.values()) {
      if (r.Result__c != 'Pass') {
        open.add(r);
      }
    }
    return open;
  }

  public static String key(
    Id sectionEnrolmentId,
    Id sectionSubjectId,
    Integer attempt
  ) {
    return sectionEnrolmentId + '|' + sectionSubjectId + '|' + attempt;
  }

  public static String termKey(Id sectionEnrolmentId, Integer term) {
    return sectionEnrolmentId + '|T' + term;
  }

  private static void upsertResults(List<Subject_Result__c> rows) {
    if (rows.isEmpty()) {
      return;
    }
    // Existing keys are left untouched (idempotent creation).
    Set<String> keys = new Set<String>();
    for (Subject_Result__c r : rows) {
      keys.add(r.Unique_Key__c);
    }
    for (Subject_Result__c existing : [
      SELECT Unique_Key__c
      FROM Subject_Result__c
      WHERE Unique_Key__c IN :keys
      WITH SYSTEM_MODE
    ]) {
      keys.remove(existing.Unique_Key__c);
    }
    List<Subject_Result__c> fresh = new List<Subject_Result__c>();
    for (Subject_Result__c r : rows) {
      if (keys.contains(r.Unique_Key__c)) {
        fresh.add(r);
      }
    }
    if (!fresh.isEmpty()) {
      Database.insert(fresh, AccessLevel.SYSTEM_MODE);
    }
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
