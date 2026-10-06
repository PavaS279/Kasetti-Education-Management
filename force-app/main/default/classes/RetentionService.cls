/**
 * Retention workflows.
 *
 * At-risk scoring (0-100, recalculated nightly by RetentionJob for active
 * enrolments):
 *   attendance below the branch threshold   +30 (below 60%: +40)
 *   last three marked sessions all absent  +25
 *   an invoice of the enrolment overdue     +15 (over 30 days: +25)
 *   course score below 65%                  +10 (below 50%: +20)
 * High is 50 or more, Medium 25 or more. A learner who becomes High gets
 * Retention follow-up "Follow-up Needed" and a task for the branch manager
 * (or the enrolment owner); staff record the outcome on the retention desk.
 *
 * Re-enrolment: learners whose class ends within the next 30 days (or ended
 * in the last 14) and who have no other active enrolment can be invited to
 * continue; the fee payer receives the Re_Enrolment_Invite message.
 */
public with sharing class RetentionService {
  public static final Set<String> ACTIVE = new Set<String>{
    'Enrolled',
    'On Hold'
  };
  public static final Set<String> OUTCOMES = new Set<String>{
    'Contacted',
    'Retained',
    'Leaving',
    'Follow-up Needed'
  };
  public static final Integer HIGH = 50;
  public static final Integer MEDIUM = 25;

  public class Risk {
    public Integer score = 0;
    public String level = 'Low';
    public List<String> reasons = new List<String>();
  }

  public class AtRisk {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Integer score;
    @AuraEnabled
    public String level;
    @AuraEnabled
    public String reasons;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String note;
    @AuraEnabled
    public Datetime assessedOn;
    @AuraEnabled
    public Decimal attendanceRate;
  }

  public class Candidate {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public Datetime invitedOn;
  }

  public class Desk {
    @AuraEnabled
    public List<AtRisk> atRisk = new List<AtRisk>();
    @AuraEnabled
    public List<Candidate> candidates = new List<Candidate>();
    @AuraEnabled
    public Integer high = 0;
    @AuraEnabled
    public Integer medium = 0;
    @AuraEnabled
    public Integer followUpNeeded = 0;
    @AuraEnabled
    public Integer retained = 0;
    @AuraEnabled
    public Datetime lastAssessed;
    @AuraEnabled
    public Boolean canRecalculate = false;
  }

  // ---------------------------------------------------------------- scoring

  /** Scores the given enrolments and saves the result; returns how many became High. */
  public static Integer assess(Set<Id> enrolmentIds) {
    List<CourseOfferingParticipant> enrolments = [
      SELECT
        Id,
        OwnerId,
        ParticipantContactId,
        ParticipantContact.Name,
        ParticipantAccountId,
        Branch__c,
        Branch__r.Attendance_Threshold__c,
        Branch__r.Branch_Manager__c,
        CourseOffering.Name,
        Attendance_Rate__c,
        Course_Score__c,
        Risk_Level__c,
        Retention_Status__c
      FROM CourseOfferingParticipant
      WHERE Id IN :enrolmentIds AND ParticipationStatus IN :ACTIVE
      WITH SYSTEM_MODE
    ];
    if (enrolments.isEmpty()) {
      return 0;
    }
    Map<Id, Integer> absencesInARow = absencesInARow(enrolmentIds);
    Map<Id, Integer> overdueDays = overdueDays(enrolmentIds);

    List<CourseOfferingParticipant> updates = new List<CourseOfferingParticipant>();
    List<Task> tasks = new List<Task>();
    for (CourseOfferingParticipant e : enrolments) {
      // Attendance rates are stored as percentages (80 = 80%).
      Decimal threshold =
        new BranchPolicy(
            new Branch__c(
              Attendance_Threshold__c = e.Branch__r?.Attendance_Threshold__c
            )
          )
          .attendanceThreshold() * 100;
      Risk risk = score(
        e.Attendance_Rate__c,
        threshold,
        absencesInARow.get(e.Id),
        overdueDays.get(e.Id),
        e.Course_Score__c
      );
      CourseOfferingParticipant change = new CourseOfferingParticipant(
        Id = e.Id,
        Risk_Score__c = risk.score,
        Risk_Level__c = risk.level,
        Risk_Reasons__c = String.join(risk.reasons, '; ').left(255),
        Risk_Assessed_On__c = System.now()
      );
      Boolean escalated =
        risk.level == 'High' &&
        e.Risk_Level__c != 'High' &&
        e.Retention_Status__c != 'Leaving';
      if (escalated) {
        change.Retention_Status__c = 'Follow-up Needed';
        tasks.add(
          new Task(
            OwnerId = e.Branch__r?.Branch_Manager__c != null
              ? e.Branch__r.Branch_Manager__c
              : e.OwnerId,
            WhatId = e.ParticipantAccountId,
            Subject = ('Retention follow-up: ' +
              e.ParticipantContact?.Name +
              ' (' +
              e.CourseOffering?.Name +
              ')')
              .left(255),
            Description = 'Risk score ' +
              risk.score +
              ': ' +
              String.join(risk.reasons, '; ') +
              '. Record the outcome on the retention desk.',
            ActivityDate = Date.today().addDays(2),
            Priority = 'High',
            Status = 'Not Started'
          )
        );
      }
      updates.add(change);
    }
    Writer writer = new Writer();
    writer.updateRecords(updates);
    writer.insertTasks(tasks);
    return tasks.size();
  }

  @TestVisible
  private static Risk score(
    Decimal attendanceRate,
    Decimal threshold,
    Integer absentInARow,
    Integer daysOverdue,
    Decimal courseScore
  ) {
    Risk risk = new Risk();
    if (
      attendanceRate != null &&
      threshold != null &&
      attendanceRate < threshold
    ) {
      Boolean severe = attendanceRate < 60;
      risk.score += severe ? 40 : 30;
      risk.reasons.add('Attendance ' + attendanceRate.setScale(0) + '%');
    }
    if (absentInARow != null && absentInARow >= 3) {
      risk.score += 25;
      risk.reasons.add('Absent ' + absentInARow + ' sessions in a row');
    }
    if (daysOverdue != null && daysOverdue > 0) {
      risk.score += daysOverdue > 30 ? 25 : 15;
      risk.reasons.add('Fees overdue ' + daysOverdue + ' days');
    }
    if (courseScore != null && courseScore < 65) {
      risk.score += courseScore < 50 ? 20 : 10;
      risk.reasons.add('Course score ' + courseScore.setScale(0) + '%');
    }
    risk.score = Math.min(risk.score, 100);
    risk.level = risk.score >= HIGH
      ? 'High'
      : risk.score >= MEDIUM ? 'Medium' : 'Low';
    return risk;
  }

  /** Absences at the end of each enrolment's marked sessions (last 3 looked at). */
  private static Map<Id, Integer> absencesInARow(Set<Id> enrolmentIds) {
    Map<Id, Integer> streak = new Map<Id, Integer>();
    Map<Id, Integer> seen = new Map<Id, Integer>();
    Set<Id> broken = new Set<Id>();
    Datetime since = System.now().addDays(-90);
    for (Session_Attendance__c mark : [
      SELECT Enrolment__c, Status__c
      FROM Session_Attendance__c
      WHERE
        Enrolment__c IN :enrolmentIds
        AND Status__c != NULL
        AND Class_Session__r.Start__c >= :since
      WITH SYSTEM_MODE
      ORDER BY Enrolment__c, Class_Session__r.Start__c DESC
    ]) {
      Id id = mark.Enrolment__c;
      Integer count = seen.containsKey(id) ? seen.get(id) : 0;
      if (count >= 3 || broken.contains(id)) {
        continue;
      }
      seen.put(id, count + 1);
      if (mark.Status__c == 'Absent') {
        streak.put(id, (streak.containsKey(id) ? streak.get(id) : 0) + 1);
      } else {
        broken.add(id);
      }
    }
    return streak;
  }

  /** Days the oldest open invoice of each enrolment is overdue. */
  private static Map<Id, Integer> overdueDays(Set<Id> enrolmentIds) {
    Map<Id, Integer> days = new Map<Id, Integer>();
    Date today = Date.today();
    for (AggregateResult row : [
      SELECT Enrolment__c enrolment, MIN(Due_Date__c) due
      FROM Student_Invoice__c
      WHERE
        Enrolment__c IN :enrolmentIds
        AND Status__c IN :BillingService.OPEN_STATUSES
        AND Balance_Due__c > 0
        AND Due_Date__c < :today
      WITH SYSTEM_MODE
      GROUP BY Enrolment__c
    ]) {
      days.put(
        (Id) row.get('enrolment'),
        ((Date) row.get('due')).daysBetween(today)
      );
    }
    return days;
  }

  // ---------------------------------------------------------------- desk

  public static Desk desk(Id branchId, String level) {
    Desk result = new Desk();
    result.canRecalculate = OpsService.isAdmin();
    String filter = 'ParticipationStatus IN :active';
    if (branchId != null) {
      filter += ' AND Branch__c = :branchId';
    }
    Map<String, Object> binds = new Map<String, Object>{
      'active' => ACTIVE,
      'branchId' => branchId
    };
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Risk_Level__c level, COUNT(Id) total, MAX(Risk_Assessed_On__c) assessed FROM CourseOfferingParticipant WHERE ' +
          filter +
          ' GROUP BY Risk_Level__c',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      String rowLevel = (String) row.get('level');
      Integer total = (Integer) row.get('total');
      if (rowLevel == 'High') {
        result.high = total;
      } else if (rowLevel == 'Medium') {
        result.medium = total;
      }
      Datetime assessed = (Datetime) row.get('assessed');
      if (
        assessed != null &&
        (result.lastAssessed == null ||
        assessed > result.lastAssessed)
      ) {
        result.lastAssessed = assessed;
      }
    }
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Retention_Status__c status, COUNT(Id) total FROM CourseOfferingParticipant WHERE ' +
          filter +
          ' AND Retention_Status__c != null GROUP BY Retention_Status__c',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      String status = (String) row.get('status');
      if (status == 'Follow-up Needed') {
        result.followUpNeeded = (Integer) row.get('total');
      } else if (status == 'Retained') {
        result.retained = (Integer) row.get('total');
      }
    }
    Set<String> levels = String.isBlank(level) || level == 'All'
      ? new Set<String>{ 'High', 'Medium' }
      : new Set<String>{ level };
    binds.put('levels', levels);
    for (
      CourseOfferingParticipant e : (List<CourseOfferingParticipant>) Database.queryWithBinds(
        'SELECT Id, ParticipantAccountId, ParticipantContact.Name, CourseOffering.Name, Branch__r.Name, ' +
          'Risk_Score__c, Risk_Level__c, Risk_Reasons__c, Retention_Status__c, Retention_Note__c, ' +
          'Risk_Assessed_On__c, Attendance_Rate__c FROM CourseOfferingParticipant WHERE ' +
          filter +
          ' AND Risk_Level__c IN :levels ORDER BY Risk_Score__c DESC, ParticipantContact.Name LIMIT 200',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AtRisk row = new AtRisk();
      row.enrolmentId = e.Id;
      row.learnerAccountId = e.ParticipantAccountId;
      row.learner = e.ParticipantContact?.Name;
      row.className = e.CourseOffering?.Name;
      row.branch = e.Branch__r?.Name;
      row.score = e.Risk_Score__c == null ? 0 : e.Risk_Score__c.intValue();
      row.level = e.Risk_Level__c;
      row.reasons = e.Risk_Reasons__c;
      row.status = e.Retention_Status__c;
      row.note = e.Retention_Note__c;
      row.assessedOn = e.Risk_Assessed_On__c;
      row.attendanceRate = e.Attendance_Rate__c;
      result.atRisk.add(row);
    }
    result.candidates = candidates(branchId);
    return result;
  }

  /** Records the outcome of a retention follow-up. */
  public static void recordFollowUp(
    Id enrolmentId,
    String status,
    String note
  ) {
    if (!OUTCOMES.contains(status)) {
      throw new AppException(
        'Choose Contacted, Retained, Leaving or Follow-up Needed.'
      );
    }
    if (status != 'Retained' && String.isBlank(note)) {
      throw new AppException('Add a note about the conversation.');
    }
    assertEditable(enrolmentId);
    new Writer()
      .updateRecords(
        new List<CourseOfferingParticipant>{
          new CourseOfferingParticipant(
            Id = enrolmentId,
            Retention_Status__c = status,
            Retention_Note__c = (String.isBlank(note)
                ? 'Retained'
                : note.trim()) +
              ' — ' +
              UserInfo.getName() +
              ', ' +
              Date.today().format()
          )
        }
      );
  }

  // ---------------------------------------------------------------- re-enrolment

  public static List<Candidate> candidates(Id branchId) {
    Datetime windowStart = Datetime.newInstance(
      Date.today().addDays(-14),
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime windowEnd = Datetime.newInstance(
      Date.today().addDays(31),
      Time.newInstance(0, 0, 0, 0)
    );
    String query =
      'SELECT Id, ParticipantContactId, ParticipantContact.Name, CourseOfferingId, CourseOffering.Name, ' +
      'CourseOffering.EndDate, Branch__r.Name, Reenrolment_Invited_On__c FROM CourseOfferingParticipant ' +
      'WHERE ParticipationStatus IN (\'Enrolled\', \'Completed\') AND CourseOffering.EndDate >= :windowStart ' +
      'AND CourseOffering.EndDate < :windowEnd' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' ORDER BY CourseOffering.EndDate, ParticipantContact.Name LIMIT 500';
    List<CourseOfferingParticipant> ending = Database.queryWithBinds(
      query,
      new Map<String, Object>{
        'windowStart' => windowStart,
        'windowEnd' => windowEnd,
        'branchId' => branchId
      },
      AccessLevel.USER_MODE
    );
    Set<Id> learners = new Set<Id>();
    for (CourseOfferingParticipant e : ending) {
      learners.add(e.ParticipantContactId);
    }
    // Learners already enrolled in a class that continues past this one are not candidates.
    Map<Id, Datetime> continuing = new Map<Id, Datetime>();
    for (CourseOfferingParticipant other : [
      SELECT ParticipantContactId, CourseOffering.EndDate
      FROM CourseOfferingParticipant
      WHERE ParticipantContactId IN :learners AND ParticipationStatus IN :ACTIVE
      WITH SYSTEM_MODE
    ]) {
      Datetime current = continuing.get(other.ParticipantContactId);
      Datetime ends = other.CourseOffering.EndDate;
      if (ends != null && (current == null || ends > current)) {
        continuing.put(other.ParticipantContactId, ends);
      }
    }
    List<Candidate> rows = new List<Candidate>();
    for (CourseOfferingParticipant e : ending) {
      Datetime latest = continuing.get(e.ParticipantContactId);
      if (latest != null && latest > e.CourseOffering.EndDate) {
        continue;
      }
      Candidate c = new Candidate();
      c.enrolmentId = e.Id;
      c.learner = e.ParticipantContact?.Name;
      c.className = e.CourseOffering?.Name;
      c.branch = e.Branch__r?.Name;
      c.endDate = e.CourseOffering.EndDate?.date();
      c.invitedOn = e.Reenrolment_Invited_On__c;
      rows.add(c);
    }
    return rows;
  }

  /** Sends Re_Enrolment_Invite to each learner's fee payer; returns messages created. */
  public static Integer invite(List<Id> enrolmentIds) {
    if (enrolmentIds == null || enrolmentIds.isEmpty()) {
      throw new AppException('Choose the learners to invite.');
    }
    List<CourseOfferingParticipant> enrolments = [
      SELECT
        Id,
        ParticipantContactId,
        ParticipantContact.Name,
        ParticipantAccountId,
        Branch__c,
        CourseOffering.Name,
        CourseOffering.EndDate
      FROM CourseOfferingParticipant
      WHERE Id IN :enrolmentIds
      WITH USER_MODE
    ];
    if (enrolments.size() != new Set<Id>(enrolmentIds).size()) {
      throw new AppException(
        'Some of the selected enrolments are not available to you.'
      );
    }
    Set<Id> learners = new Set<Id>();
    for (CourseOfferingParticipant e : enrolments) {
      learners.add(e.ParticipantContactId);
    }
    Map<Id, Id> payers = MessageService.feePayersOf(learners);
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    List<CourseOfferingParticipant> updates = new List<CourseOfferingParticipant>();
    for (CourseOfferingParticipant e : enrolments) {
      MessageService.Notice notice = new MessageService.Notice();
      notice.recipientId = payers.get(e.ParticipantContactId);
      notice.learnerContactId = e.ParticipantContactId;
      notice.learnerAccountId = e.ParticipantAccountId;
      notice.branchId = e.Branch__c;
      notice.relatedId = e.Id;
      notice.dedupSuffix = String.valueOf(Date.today());
      notice.values.put('LearnerName', e.ParticipantContact?.Name);
      notice.values.put('ClassName', e.CourseOffering?.Name);
      notice.values.put(
        'EndDate',
        e.CourseOffering.EndDate == null
          ? 'soon'
          : e.CourseOffering.EndDate.date().format()
      );
      notices.add(notice);
      updates.add(
        new CourseOfferingParticipant(
          Id = e.Id,
          Reenrolment_Invited_On__c = System.now()
        )
      );
    }
    Integer created = MessageService.notify('Re_Enrolment_Invite', notices);
    new Writer().updateRecords(updates);
    return created;
  }

  // ---------------------------------------------------------------- helpers

  private static void assertEditable(Id enrolmentId) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :enrolmentId
    ];
    if (access.isEmpty() || !access[0].HasEditAccess) {
      throw new AppException('You cannot update this enrolment.');
    }
  }

  /** Risk and follow-up fields are system-managed. */
  private without sharing class Writer {
    void updateRecords(List<CourseOfferingParticipant> rows) {
      Database.update(rows, AccessLevel.SYSTEM_MODE);
    }
    void insertTasks(List<Task> rows) {
      Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
    }
  }
}
