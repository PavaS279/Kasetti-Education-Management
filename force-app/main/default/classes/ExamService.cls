/**
 * Exams and hall tickets (F4.10).
 *
 * An exam of a branch has papers, one per class (date, time, duration,
 * marks). Learners enrolled in those classes are registered as candidates
 * with a hall ticket number; eligibility is checked (attendance below the
 * exam's or branch's minimum, optionally overdue fees) and withheld
 * candidates can be allowed by someone with KEM Eligibility Override.
 * Eligible candidates are seated in rooms, hall tickets are issued as PDFs
 * (in the portal) and families are told. Marks are entered per paper and,
 * when published, become a published "Exam" assessment in the class
 * gradebook, so they count in the class grade.
 */
public with sharing class ExamService {
  public static final String OVERRIDE_PERMISSION = 'KEM_Override_Eligibility';
  public static final Set<String> CLOSED = new Set<String>{
    'Results Published',
    'Cancelled'
  };

  public class ExamSummary {
    @AuraEnabled
    public Id examId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String examType;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer papers = 0;
    @AuraEnabled
    public Integer candidates = 0;
  }

  public class PaperRow {
    @AuraEnabled
    public Id paperId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Id classId;
    @AuraEnabled
    public Date paperDate;
    @AuraEnabled
    public String startTime;
    @AuraEnabled
    public Integer durationMinutes;
    @AuraEnabled
    public Decimal maxMarks;
    @AuraEnabled
    public Decimal passMarks;
    @AuraEnabled
    public String marksStatus;
    @AuraEnabled
    public Id assessmentId;
  }

  public class CandidateRow {
    @AuraEnabled
    public Id candidateId;
    @AuraEnabled
    public String hallTicket;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String reason;
    @AuraEnabled
    public String overrideReason;
    @AuraEnabled
    public Decimal attendance;
    @AuraEnabled
    public Decimal overdue;
    @AuraEnabled
    public String room;
    @AuraEnabled
    public String seat;
  }

  public class ExamDetail {
    @AuraEnabled
    public ExamSummary exam;
    @AuraEnabled
    public String instructions;
    @AuraEnabled
    public List<PaperRow> papers = new List<PaperRow>();
    @AuraEnabled
    public List<CandidateRow> candidates = new List<CandidateRow>();
    @AuraEnabled
    public Map<String, Integer> counts = new Map<String, Integer>();
    @AuraEnabled
    public Boolean canManage = false;
    @AuraEnabled
    public Boolean canOverride = false;
    @AuraEnabled
    public List<RoomOption> rooms = new List<RoomOption>();
  }

  public class RoomOption {
    @AuraEnabled
    public Id roomId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer capacity;
  }

  public class MarkRow {
    @AuraEnabled
    public Id candidateId { get; set; }
    @AuraEnabled
    public String hallTicket { get; set; }
    @AuraEnabled
    public String learner { get; set; }
    @AuraEnabled
    public Id learnerContactId { get; set; }
    @AuraEnabled
    public Id enrolmentId { get; set; }
    @AuraEnabled
    public Decimal marks { get; set; }
    @AuraEnabled
    public Boolean absent { get; set; }
  }

  public class MarkSheet {
    @AuraEnabled
    public PaperRow paper;
    @AuraEnabled
    public List<MarkRow> rows = new List<MarkRow>();
    @AuraEnabled
    public Boolean editable = false;
  }

  public class StepResult {
    @AuraEnabled
    public Integer processed = 0;
    @AuraEnabled
    public Integer skipped = 0;
    @AuraEnabled
    public List<String> notes = new List<String>();
  }

  // ---------------------------------------------------------------- reading

  public static List<ExamSummary> exams(Id branchId) {
    List<ExamSummary> result = new List<ExamSummary>();
    for (
      Exam__c e : (List<Exam__c>) Database.queryWithBinds(
        'SELECT Id, Name, Exam_Code__c, Branch__r.Name, Exam_Type__c, Start_Date__c, End_Date__c, Status__c, ' +
          '(SELECT Id FROM Papers__r), (SELECT Id FROM Candidates__r) FROM Exam__c' +
          (branchId == null ? '' : ' WHERE Branch__c = :branchId') +
          ' ORDER BY Start_Date__c DESC NULLS FIRST, Name LIMIT 100',
        new Map<String, Object>{ 'branchId' => branchId },
        AccessLevel.USER_MODE
      )
    ) {
      result.add(summary(e));
    }
    return result;
  }

  public static ExamDetail exam(Id examId) {
    Exam__c e = load(examId);
    ExamDetail detail = new ExamDetail();
    detail.exam = summary(e);
    detail.instructions = e.Instructions__c;
    detail.canManage = Schema.SObjectType.Exam_Candidate__c.isCreateable();
    detail.canOverride = FeatureManagement.checkPermission(OVERRIDE_PERMISSION);
    for (Exam_Paper__c p : papers(examId)) {
      detail.papers.add(paperRow(p));
    }
    for (
      String s : new List<String>{
        'Registered',
        'Eligible',
        'Withheld',
        'Ticket Issued'
      }
    ) {
      detail.counts.put(s, 0);
    }
    for (Exam_Candidate__c c : [
      SELECT
        Id,
        Name,
        Learner_Account__c,
        Learner_Account__r.Name,
        Status__c,
        Withheld_Reason__c,
        Override_Reason__c,
        Attendance_Rate__c,
        Overdue_Amount__c,
        Room__r.Name,
        Seat_Number__c
      FROM Exam_Candidate__c
      WHERE Exam__c = :examId
      WITH USER_MODE
      ORDER BY Name
    ]) {
      CandidateRow row = new CandidateRow();
      row.candidateId = c.Id;
      row.hallTicket = c.Name;
      row.learnerAccountId = c.Learner_Account__c;
      row.learner = c.Learner_Account__r?.Name;
      row.status = c.Status__c;
      row.reason = c.Withheld_Reason__c;
      row.overrideReason = c.Override_Reason__c;
      row.attendance = c.Attendance_Rate__c;
      row.overdue = c.Overdue_Amount__c;
      row.room = c.Room__r?.Name;
      row.seat = c.Seat_Number__c;
      detail.candidates.add(row);
      detail.counts.put(c.Status__c, detail.counts.get(c.Status__c) + 1);
    }
    for (Room__c r : [
      SELECT Id, Name, Capacity__c
      FROM Room__c
      WHERE
        Branch__c = :e.Branch__c
        AND Active__c = TRUE
        AND Room_Type__c != 'Virtual'
      WITH USER_MODE
      ORDER BY Name
    ]) {
      RoomOption option = new RoomOption();
      option.roomId = r.Id;
      option.name = r.Name;
      option.capacity = r.Capacity__c == null ? 0 : r.Capacity__c.intValue();
      detail.rooms.add(option);
    }
    return detail;
  }

  // ---------------------------------------------------------------- candidates

  /** Registers every learner enrolled in the exam's classes (once each). */
  public static StepResult registerCandidates(Id examId) {
    assertCanManage();
    Exam__c e = loadOpen(examId);
    Set<Id> classIds = new Set<Id>();
    for (Exam_Paper__c p : papers(examId)) {
      classIds.add(p.Course_Offering__c);
    }
    if (classIds.isEmpty()) {
      throw new AppException('Add the exam papers (one per class) first.');
    }
    Set<Id> existing = new Set<Id>();
    Integer sequence = 0;
    for (Exam_Candidate__c c : [
      SELECT Learner_Account__c, Name
      FROM Exam_Candidate__c
      WHERE Exam__c = :examId
      WITH SYSTEM_MODE
    ]) {
      existing.add(c.Learner_Account__c);
      sequence = Math.max(sequence, sequenceOf(c.Name));
    }
    StepResult result = new StepResult();
    List<Exam_Candidate__c> inserts = new List<Exam_Candidate__c>();
    Set<Id> added = new Set<Id>();
    for (CourseOfferingParticipant enrolment : [
      SELECT ParticipantAccountId, ParticipantAccount.Name
      FROM CourseOfferingParticipant
      WHERE CourseOfferingId IN :classIds AND ParticipationStatus = 'Enrolled'
      WITH USER_MODE
      ORDER BY ParticipantAccount.Name
    ]) {
      Id learner = enrolment.ParticipantAccountId;
      if (existing.contains(learner) || added.contains(learner)) {
        result.skipped++;
        continue;
      }
      added.add(learner);
      sequence++;
      inserts.add(
        new Exam_Candidate__c(
          Exam__c = examId,
          Name = e.Exam_Code__c +
            '-' +
            String.valueOf(sequence).leftPad(4, '0'),
          Learner_Account__c = learner,
          Status__c = 'Registered',
          Unique_Key__c = examId + ':' + learner
        )
      );
    }
    new Writer().insertRecords(inserts);
    if (e.Status__c == 'Draft' && !inserts.isEmpty()) {
      new Writer()
        .updateRecords(
          new List<SObject>{ new Exam__c(Id = examId, Status__c = 'Scheduled') }
        );
    }
    result.processed = inserts.size();
    return result;
  }

  /**
   * Checks every candidate without a hall ticket: attendance in the exam's
   * classes against the minimum and, if the exam says so, overdue invoices.
   */
  public static StepResult checkEligibility(Id examId) {
    assertCanManage();
    Exam__c e = loadOpen(examId);
    Decimal minimum = e.Min_Attendance__c != null
      ? e.Min_Attendance__c
      : new BranchPolicy(
            [
              SELECT Attendance_Threshold__c
              FROM Branch__c
              WHERE Id = :e.Branch__c
              WITH SYSTEM_MODE
            ]
          )
          .attendanceThreshold() * 100;
    Set<Id> classIds = new Set<Id>();
    for (Exam_Paper__c p : papers(examId)) {
      classIds.add(p.Course_Offering__c);
    }
    List<Exam_Candidate__c> candidates = [
      SELECT Id, Learner_Account__c, Status__c, Override_Reason__c
      FROM Exam_Candidate__c
      WHERE Exam__c = :examId AND Status__c != 'Ticket Issued'
      WITH SYSTEM_MODE
    ];
    Set<Id> learners = new Set<Id>();
    for (Exam_Candidate__c c : candidates) {
      learners.add(c.Learner_Account__c);
    }
    Map<Id, Decimal> attendance = new Map<Id, Decimal>();
    for (CourseOfferingParticipant enrolment : [
      SELECT ParticipantAccountId, Attendance_Rate__c
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId IN :classIds
        AND ParticipantAccountId IN :learners
        AND ParticipationStatus = 'Enrolled'
      WITH SYSTEM_MODE
    ]) {
      if (enrolment.Attendance_Rate__c == null) {
        continue;
      }
      Decimal current = attendance.get(enrolment.ParticipantAccountId);
      if (current == null || enrolment.Attendance_Rate__c < current) {
        attendance.put(
          enrolment.ParticipantAccountId,
          enrolment.Attendance_Rate__c
        );
      }
    }
    Map<Id, Decimal> overdue = new Map<Id, Decimal>();
    Date today = Date.today();
    for (AggregateResult row : [
      SELECT Learner_Account__c learner, SUM(Balance_Due__c) due
      FROM Student_Invoice__c
      WHERE
        Learner_Account__c IN :learners
        AND Status__c IN :BillingService.OPEN_STATUSES
        AND Balance_Due__c > 0
        AND Due_Date__c < :today
      WITH SYSTEM_MODE
      GROUP BY Learner_Account__c
    ]) {
      overdue.put((Id) row.get('learner'), (Decimal) row.get('due'));
    }
    StepResult result = new StepResult();
    List<SObject> updates = new List<SObject>();
    for (Exam_Candidate__c c : candidates) {
      Decimal rate = attendance.get(c.Learner_Account__c);
      Decimal due = overdue.containsKey(c.Learner_Account__c)
        ? overdue.get(c.Learner_Account__c)
        : 0;
      List<String> reasons = new List<String>();
      if (rate != null && rate < minimum) {
        reasons.add(
          'attendance ' +
            rate.setScale(1) +
            '% is below ' +
            minimum.setScale(0) +
            '%'
        );
      }
      if (e.Block_Overdue_Fees__c && due > 0) {
        reasons.add('fees of ' + due.setScale(2) + ' are overdue');
      }
      Boolean allowed =
        reasons.isEmpty() || String.isNotBlank(c.Override_Reason__c);
      updates.add(
        new Exam_Candidate__c(
          Id = c.Id,
          Status__c = allowed ? 'Eligible' : 'Withheld',
          Withheld_Reason__c = reasons.isEmpty()
            ? null
            : String.join(reasons, '; ').left(255),
          Attendance_Rate__c = rate,
          Overdue_Amount__c = due
        )
      );
      if (allowed) {
        result.processed++;
      } else {
        result.skipped++;
      }
    }
    new Writer().updateRecords(updates);
    result.notes.add(
      result.processed +
        ' eligible, ' +
        result.skipped +
        ' withheld (minimum attendance ' +
        minimum.setScale(0) +
        '%).'
    );
    return result;
  }

  /** Allows a withheld candidate (KEM Eligibility Override), with a reason. */
  public static void overrideCandidate(Id candidateId, String reason) {
    if (!FeatureManagement.checkPermission(OVERRIDE_PERMISSION)) {
      throw new AppException(
        'Only staff with KEM Eligibility Override can allow a withheld candidate.'
      );
    }
    if (String.isBlank(reason) || reason.trim().length() < 5) {
      throw new AppException('Give the reason for allowing this candidate.');
    }
    Exam_Candidate__c c = candidate(candidateId);
    if (c.Status__c != 'Withheld') {
      throw new AppException('Only withheld candidates need to be allowed.');
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Exam_Candidate__c(
            Id = c.Id,
            Status__c = 'Eligible',
            Override_Reason__c = (reason.trim() +
              ' (' +
              UserInfo.getName() +
              ')')
              .left(255)
          )
        }
      );
  }

  /** Seats eligible candidates without a ticket in the chosen rooms, in hall ticket order. */
  public static StepResult allocateSeats(Id examId, List<Id> roomIds) {
    assertCanManage();
    Exam__c e = loadOpen(examId);
    if (roomIds == null || roomIds.isEmpty()) {
      throw new AppException('Choose at least one room.');
    }
    Map<Id, Room__c> rooms = new Map<Id, Room__c>(
      [
        SELECT Id, Name, Capacity__c
        FROM Room__c
        WHERE Id IN :roomIds AND Branch__c = :e.Branch__c AND Active__c = TRUE
        WITH USER_MODE
      ]
    );
    List<Exam_Candidate__c> candidates = [
      SELECT Id, Name
      FROM Exam_Candidate__c
      WHERE Exam__c = :examId AND Status__c = 'Eligible'
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
    Integer seats = 0;
    for (Room__c r : rooms.values()) {
      seats += r.Capacity__c == null ? 0 : r.Capacity__c.intValue();
    }
    if (seats < candidates.size()) {
      throw new AppException(
        'The chosen rooms seat ' +
          seats +
          ' but ' +
          candidates.size() +
          ' candidates are eligible. Add a room.'
      );
    }
    List<SObject> updates = new List<SObject>();
    Integer index = 0;
    for (Id roomId : roomIds) {
      Room__c room = rooms.get(roomId);
      if (room == null) {
        continue;
      }
      Integer capacity = room.Capacity__c == null
        ? 0
        : room.Capacity__c.intValue();
      for (
        Integer seat = 1; seat <= capacity && index < candidates.size(); seat++
      ) {
        updates.add(
          new Exam_Candidate__c(
            Id = candidates[index].Id,
            Room__c = room.Id,
            Seat_Number__c = (room.Name +
              '-' +
              String.valueOf(seat).leftPad(2, '0'))
              .left(20)
          )
        );
        index++;
      }
    }
    new Writer().updateRecords(updates);
    StepResult result = new StepResult();
    result.processed = updates.size();
    return result;
  }

  /**
   * Issues hall tickets to eligible, seated candidates (PDF in the portal,
   * message to the fee payer) and tells families of withheld candidates.
   */
  public static StepResult issueTickets(Id examId) {
    assertCanManage();
    Exam__c e = loadOpen(examId);
    List<Exam_Paper__c> examPapers = papers(examId);
    if (examPapers.isEmpty()) {
      throw new AppException('Add the exam papers first.');
    }
    StepResult result = new StepResult();
    List<Exam_Candidate__c> ready = new List<Exam_Candidate__c>();
    List<Exam_Candidate__c> withheld = new List<Exam_Candidate__c>();
    for (Exam_Candidate__c c : [
      SELECT
        Id,
        Name,
        Status__c,
        Seat_Number__c,
        Withheld_Reason__c,
        Learner_Account__c,
        Learner_Account__r.Name,
        Learner_Account__r.PersonContactId,
        Ticket_Issued_On__c
      FROM Exam_Candidate__c
      WHERE Exam__c = :examId AND Status__c IN ('Eligible', 'Withheld')
      WITH SYSTEM_MODE
    ]) {
      if (c.Status__c == 'Withheld') {
        withheld.add(c);
      } else if (String.isBlank(c.Seat_Number__c)) {
        result.skipped++;
      } else {
        ready.add(c);
      }
    }
    if (result.skipped > 0) {
      result.notes.add(
        result.skipped +
        ' eligible candidate(s) have no seat yet: allocate seats first.'
      );
    }
    List<SObject> updates = new List<SObject>();
    Set<Id> issued = new Set<Id>();
    for (Exam_Candidate__c c : ready) {
      updates.add(
        new Exam_Candidate__c(
          Id = c.Id,
          Status__c = 'Ticket Issued',
          Ticket_Issued_On__c = System.now()
        )
      );
      issued.add(c.Id);
    }
    if (!ready.isEmpty() && e.Status__c != 'Hall Tickets Issued') {
      updates.add(new Exam__c(Id = examId, Status__c = 'Hall Tickets Issued'));
    }
    new Writer().updateRecords(updates);
    result.processed = ready.size();
    if (!issued.isEmpty()) {
      DocumentService.enqueue(issued, DocumentService.HALL_TICKET);
    }
    notifyFamilies(e, examPapers[0], ready, 'Hall_Ticket_Issued');
    notifyFamilies(e, examPapers[0], withheld, 'Hall_Ticket_Withheld');
    if (!withheld.isEmpty()) {
      result.notes.add(
        withheld.size() + ' withheld candidate(s) were told why.'
      );
    }
    return result;
  }

  private static void notifyFamilies(
    Exam__c e,
    Exam_Paper__c first,
    List<Exam_Candidate__c> candidates,
    String template
  ) {
    if (candidates.isEmpty()) {
      return;
    }
    Set<Id> learnerContacts = new Set<Id>();
    for (Exam_Candidate__c c : candidates) {
      learnerContacts.add(c.Learner_Account__r.PersonContactId);
    }
    Map<Id, Id> payers = MessageService.feePayersOf(learnerContacts);
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    for (Exam_Candidate__c c : candidates) {
      MessageService.Notice n = new MessageService.Notice();
      n.recipientId = payers.get(c.Learner_Account__r.PersonContactId);
      n.learnerContactId = c.Learner_Account__r.PersonContactId;
      n.learnerAccountId = c.Learner_Account__c;
      n.branchId = e.Branch__c;
      n.relatedId = c.Id;
      // One message per state: a withheld candidate who is later issued a ticket hears both.
      n.dedupSuffix = template;
      n.values.put('LearnerName', c.Learner_Account__r.Name);
      n.values.put('ExamName', e.Name);
      n.values.put('HallTicket', c.Name);
      n.values.put(
        'FirstPaper',
        first.Paper_Date__c.format() +
        (String.isBlank(first.Start_Time__c)
          ? ''
          : ' at ' + first.Start_Time__c)
      );
      n.values.put(
        'Reason',
        String.isBlank(c.Withheld_Reason__c)
          ? 'please contact the branch'
          : c.Withheld_Reason__c
      );
      notices.add(n);
    }
    MessageService.notify(template, notices);
  }

  // ---------------------------------------------------------------- marks

  /** Candidates of the paper's class with their marks. */
  public static MarkSheet markSheet(Id paperId) {
    Exam_Paper__c p = paper(paperId);
    MarkSheet sheet = new MarkSheet();
    sheet.paper = paperRow(p);
    sheet.editable =
      p.Marks_Status__c != 'Published' &&
      Schema.SObjectType.Exam_Mark__c.isCreateable();
    Map<Id, CourseOfferingParticipant> enrolments = new Map<Id, CourseOfferingParticipant>();
    for (CourseOfferingParticipant enrolment : [
      SELECT Id, ParticipantAccountId, ParticipantContactId
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :p.Course_Offering__c
        AND ParticipationStatus IN ('Enrolled', 'Completed')
      WITH SYSTEM_MODE
    ]) {
      enrolments.put(enrolment.ParticipantAccountId, enrolment);
    }
    Map<Id, Exam_Mark__c> marks = new Map<Id, Exam_Mark__c>();
    for (Exam_Mark__c m : [
      SELECT Candidate__c, Marks__c, Absent__c
      FROM Exam_Mark__c
      WHERE Paper__c = :paperId
      WITH USER_MODE
    ]) {
      marks.put(m.Candidate__c, m);
    }
    for (Exam_Candidate__c c : [
      SELECT Id, Name, Learner_Account__c, Learner_Account__r.Name, Status__c
      FROM Exam_Candidate__c
      WHERE Exam__c = :p.Exam__c AND Learner_Account__c IN :enrolments.keySet()
      WITH USER_MODE
      ORDER BY Name
    ]) {
      CourseOfferingParticipant enrolment = enrolments.get(
        c.Learner_Account__c
      );
      MarkRow row = new MarkRow();
      row.candidateId = c.Id;
      row.hallTicket = c.Name;
      row.learner = c.Learner_Account__r.Name;
      row.learnerContactId = enrolment.ParticipantContactId;
      row.enrolmentId = enrolment.Id;
      Exam_Mark__c m = marks.get(c.Id);
      row.marks = m?.Marks__c;
      row.absent = m == null ? false : m.Absent__c;
      sheet.rows.add(row);
    }
    return sheet;
  }

  public static void saveMarks(Id paperId, List<MarkRow> rows) {
    if (!Schema.SObjectType.Exam_Mark__c.isCreateable()) {
      throw new AppException('You do not have permission to enter exam marks.');
    }
    Exam_Paper__c p = paper(paperId);
    if (p.Marks_Status__c == 'Published') {
      throw new AppException('Published marks are locked.');
    }
    MarkSheet sheet = markSheet(paperId);
    Map<Id, MarkRow> allowed = new Map<Id, MarkRow>();
    for (MarkRow r : sheet.rows) {
      allowed.put(r.candidateId, r);
    }
    List<Exam_Mark__c> upserts = new List<Exam_Mark__c>();
    for (MarkRow row : rows == null ? new List<MarkRow>() : rows) {
      MarkRow known = allowed.get(row.candidateId);
      if (known == null) {
        continue;
      }
      Boolean absent = row.absent == true;
      if (row.marks == null && !absent) {
        continue;
      }
      if (!absent && (row.marks < 0 || row.marks > p.Max_Marks__c)) {
        throw new AppException(
          known.learner +
            ': marks must be between 0 and ' +
            p.Max_Marks__c.stripTrailingZeros().toPlainString() +
            '.'
        );
      }
      upserts.add(
        new Exam_Mark__c(
          Paper__c = paperId,
          Candidate__c = row.candidateId,
          Enrolment__c = known.enrolmentId,
          Marks__c = absent ? null : row.marks,
          Absent__c = absent,
          Unique_Key__c = paperId + ':' + row.candidateId
        )
      );
    }
    if (upserts.isEmpty()) {
      throw new AppException('Enter marks for at least one candidate.');
    }
    new Writer().upsertMarks(upserts);
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Exam_Paper__c(Id = paperId, Marks_Status__c = 'Draft')
        }
      );
  }

  /**
   * Publishes a paper's marks into the class gradebook: a published Exam
   * assessment with one result per candidate; class grades are recalculated.
   */
  public static Id publishMarks(Id paperId) {
    Exam_Paper__c p = paper(paperId);
    if (p.Marks_Status__c != 'Draft') {
      throw new AppException(
        p.Marks_Status__c == 'Published'
          ? 'These marks are already published.'
          : 'Enter the marks first.'
      );
    }
    MarkSheet sheet = markSheet(paperId);
    List<AssessmentService.ResultRow> results = new List<AssessmentService.ResultRow>();
    for (MarkRow r : sheet.rows) {
      if (r.marks == null && r.absent != true) {
        continue;
      }
      AssessmentService.ResultRow row = new AssessmentService.ResultRow();
      row.learnerContactId = r.learnerContactId;
      row.enrolmentId = r.enrolmentId;
      row.learnerName = r.learner;
      row.score = r.marks;
      row.absent = r.absent == true;
      results.add(row);
    }
    Course_Assessment__c assessment = new Course_Assessment__c(
      Name = (p.Exam__r.Name + ' – ' + p.Name).left(80),
      Course_Offering__c = p.Course_Offering__c,
      Assessment_Type__c = 'Exam',
      Max_Score__c = p.Max_Marks__c,
      Weight__c = p.Weight__c,
      Assessment_Date__c = p.Paper_Date__c,
      Description__c = 'Published from exam ' + p.Exam__r.Exam_Code__c
    );
    Savepoint sp = Database.setSavepoint();
    try {
      insert as user assessment;
      AssessmentService.saveResults(assessment.Id, results);
      AssessmentService.publish(assessment.Id);
      new Writer()
        .updateRecords(
          new List<SObject>{
            new Exam_Paper__c(
              Id = paperId,
              Marks_Status__c = 'Published',
              Assessment__c = assessment.Id
            )
          }
        );
      Integer open = [
        SELECT COUNT()
        FROM Exam_Paper__c
        WHERE
          Exam__c = :p.Exam__c
          AND Marks_Status__c != 'Published'
          AND Id != :paperId
        WITH SYSTEM_MODE
      ];
      if (open == 0) {
        new Writer()
          .updateRecords(
            new List<SObject>{
              new Exam__c(Id = p.Exam__c, Status__c = 'Results Published')
            }
          );
      }
    } catch (Exception ex) {
      Database.rollback(sp);
      throw ex;
    }
    return assessment.Id;
  }

  // ---------------------------------------------------------------- helpers

  private static void assertCanManage() {
    if (!Schema.SObjectType.Exam_Candidate__c.isCreateable()) {
      throw new AppException('You do not have permission to manage exams.');
    }
  }

  private static Exam__c load(Id examId) {
    List<Exam__c> rows = [
      SELECT
        Id,
        Name,
        Exam_Code__c,
        Branch__c,
        Branch__r.Name,
        Exam_Type__c,
        Start_Date__c,
        End_Date__c,
        Status__c,
        Instructions__c,
        Min_Attendance__c,
        Block_Overdue_Fees__c,
        (SELECT Id FROM Papers__r),
        (SELECT Id FROM Candidates__r)
      FROM Exam__c
      WHERE Id = :examId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Exam not found.');
    }
    return rows[0];
  }

  private static Exam__c loadOpen(Id examId) {
    Exam__c e = load(examId);
    if (CLOSED.contains(e.Status__c)) {
      throw new AppException('This exam is ' + e.Status__c.toLowerCase() + '.');
    }
    return e;
  }

  private static List<Exam_Paper__c> papers(Id examId) {
    return [
      SELECT
        Id,
        Name,
        Exam__c,
        Course_Offering__c,
        Course_Offering__r.Name,
        Paper_Date__c,
        Start_Time__c,
        Duration_Minutes__c,
        Max_Marks__c,
        Pass_Marks__c,
        Weight__c,
        Marks_Status__c,
        Assessment__c
      FROM Exam_Paper__c
      WHERE Exam__c = :examId
      WITH USER_MODE
      ORDER BY Paper_Date__c, Start_Time__c, Name
    ];
  }

  private static Exam_Paper__c paper(Id paperId) {
    List<Exam_Paper__c> rows = [
      SELECT
        Id,
        Name,
        Exam__c,
        Exam__r.Name,
        Exam__r.Exam_Code__c,
        Course_Offering__c,
        Course_Offering__r.Name,
        Paper_Date__c,
        Start_Time__c,
        Duration_Minutes__c,
        Max_Marks__c,
        Pass_Marks__c,
        Weight__c,
        Marks_Status__c,
        Assessment__c
      FROM Exam_Paper__c
      WHERE Id = :paperId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Exam paper not found.');
    }
    return rows[0];
  }

  private static Exam_Candidate__c candidate(Id candidateId) {
    List<Exam_Candidate__c> rows = [
      SELECT Id, Status__c, Exam__c
      FROM Exam_Candidate__c
      WHERE Id = :candidateId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Candidate not found.');
    }
    return rows[0];
  }

  private static PaperRow paperRow(Exam_Paper__c p) {
    PaperRow row = new PaperRow();
    row.paperId = p.Id;
    row.name = p.Name;
    row.classId = p.Course_Offering__c;
    row.className = p.Course_Offering__r?.Name;
    row.paperDate = p.Paper_Date__c;
    row.startTime = p.Start_Time__c;
    row.durationMinutes = p.Duration_Minutes__c == null
      ? null
      : p.Duration_Minutes__c.intValue();
    row.maxMarks = p.Max_Marks__c;
    row.passMarks = p.Pass_Marks__c;
    row.marksStatus = p.Marks_Status__c;
    row.assessmentId = p.Assessment__c;
    return row;
  }

  private static ExamSummary summary(Exam__c e) {
    ExamSummary s = new ExamSummary();
    s.examId = e.Id;
    s.name = e.Name;
    s.code = e.Exam_Code__c;
    s.branch = e.Branch__r?.Name;
    s.examType = e.Exam_Type__c;
    s.startDate = e.Start_Date__c;
    s.endDate = e.End_Date__c;
    s.status = e.Status__c;
    s.papers = e.Papers__r == null ? 0 : e.Papers__r.size();
    s.candidates = e.Candidates__r == null ? 0 : e.Candidates__r.size();
    return s;
  }

  private static Integer sequenceOf(String hallTicket) {
    try {
      return Integer.valueOf(hallTicket.substringAfterLast('-'));
    } catch (Exception e) {
      return 0;
    }
  }

  /** System-mode writes of system-managed fields, after the checks above. */
  private without sharing class Writer {
    void insertRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
      }
    }
    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
    void upsertMarks(List<Exam_Mark__c> marks) {
      Database.upsert(
        marks,
        Exam_Mark__c.Unique_Key__c,
        AccessLevel.SYSTEM_MODE
      );
    }
  }
}
