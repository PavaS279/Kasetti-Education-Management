/**
 * The Einstein assistants. Each method gathers the facts the prompt needs
 * from records the user can see (user mode), passes them to AiService and
 * returns a draft for a person to review. Nothing here sends, saves to a
 * learner record or changes money without a separate, explicit staff action.
 */
public with sharing class AiAssistantService {
  // ---------------------------------------------------------------- F4.2 enquiry reply

  public static AiService.Result draftEnquiryReply(
    Id leadId,
    String counsellorNote
  ) {
    Lead enquiry = [
      SELECT
        Id,
        FirstName,
        Guardian_First_Name__c,
        Learner_Birthdate__c,
        Enquiry_Channel__c,
        Preferred_Delivery_Mode__c,
        Description,
        Branch__c,
        Branch__r.Name,
        Branch__r.City__c,
        Branch__r.Phone__c,
        Branch__r.Email__c,
        Branch__r.Operating_Hours__c,
        Interested_Course__c,
        Interested_Course__r.Name,
        Interested_Course__r.Entry_Requirements__c,
        Interested_Course__r.Minimum_Age__c,
        Interested_Course__r.Maximum_Age__c
      FROM Lead
      WHERE Id = :leadId
      WITH USER_MODE
    ];
    Map<String, String> v = new Map<String, String>();
    v.put(
      'RecipientName',
      firstNonBlank(enquiry.Guardian_First_Name__c, enquiry.FirstName)
    );
    v.put('LearnerName', enquiry.FirstName);
    v.put(
      'LearnerAge',
      enquiry.Learner_Birthdate__c == null
        ? 'not given'
        : String.valueOf(
            Math.floor(
              enquiry.Learner_Birthdate__c.daysBetween(Date.today()) / 365.25
            )
          )
    );
    v.put('Channel', enquiry.Enquiry_Channel__c);
    v.put(
      'DeliveryMode',
      firstNonBlank(enquiry.Preferred_Delivery_Mode__c, 'not stated')
    );
    v.put('EnquiryNotes', firstNonBlank(enquiry.Description, 'none'));
    v.put('CounsellorNote', firstNonBlank(counsellorNote, 'none'));
    v.put(
      'Branch',
      enquiry.Branch__r == null
        ? 'not chosen'
        : join(
            new List<String>{
              enquiry.Branch__r.Name,
              enquiry.Branch__r.City__c,
              enquiry.Branch__r.Operating_Hours__c == null
                ? null
                : 'open ' + enquiry.Branch__r.Operating_Hours__c,
              enquiry.Branch__r.Phone__c == null
                ? null
                : 'phone ' + enquiry.Branch__r.Phone__c,
              enquiry.Branch__r.Email__c == null
                ? null
                : 'email ' + enquiry.Branch__r.Email__c
            }
          )
    );
    v.put('CounsellorName', UserInfo.getFirstName());
    if (enquiry.Interested_Course__c == null) {
      v.put('Course', 'not chosen');
      v.put('Prices', 'not applicable');
      v.put('Classes', 'not applicable');
    } else {
      LearningCourse course = enquiry.Interested_Course__r;
      v.put(
        'Course',
        join(
          new List<String>{
            course.Name,
            course.Minimum_Age__c == null &&
              course.Maximum_Age__c == null
              ? null
              : 'ages ' +
                nvl(course.Minimum_Age__c) +
                '–' +
                nvl(course.Maximum_Age__c),
            course.Entry_Requirements__c == null
              ? null
              : 'entry requirements: ' + course.Entry_Requirements__c
          }
        )
      );
      v.put('Prices', prices(course.Id, enquiry.Branch__c));
      v.put('Classes', upcomingClasses(course.Id, enquiry.Branch__c));
    }
    return AiService.generateOrFail(
      'Enquiry_Reply',
      v,
      enquiry.Id,
      enquiry.Branch__c
    );
  }

  private static String prices(Id courseId, Id branchId) {
    Date today = Date.today();
    Map<String, Fee_Price__c> best = new Map<String, Fee_Price__c>();
    for (Fee_Price__c p : [
      SELECT
        Fee_Type__c,
        Billing_Frequency__c,
        Amount__c,
        Branch__c,
        Delivery_Mode__c
      FROM Fee_Price__c
      WHERE
        Learning_Course__c = :courseId
        AND Active__c = TRUE
        AND Effective_From__c <= :today
        AND (Effective_To__c = NULL
        OR Effective_To__c >= :today)
        AND (Branch__c = NULL
        OR Branch__c = :branchId)
      WITH USER_MODE
      ORDER BY Branch__c NULLS LAST
    ]) {
      String key = p.Fee_Type__c + '|' + p.Billing_Frequency__c;
      // Branch-specific prices sort first and take precedence.
      if (!best.containsKey(key)) {
        best.put(key, p);
      }
    }
    List<String> lines = new List<String>();
    for (Fee_Price__c p : best.values()) {
      lines.add(
        p.Fee_Type__c +
          ' ' +
          MessageService.money(p.Amount__c) +
          ' (' +
          p.Billing_Frequency__c +
          ')'
      );
    }
    return lines.isEmpty()
      ? 'no published prices; say the branch will confirm fees'
      : String.join(lines, '; ') + ' (tax may apply)';
  }

  private static String upcomingClasses(Id courseId, Id branchId) {
    Datetime now = System.now();
    List<String> lines = new List<String>();
    for (CourseOffering c : [
      SELECT
        Id,
        Name,
        StartDate,
        Class_Status__c,
        Seats_Available__c,
        Delivery_Mode__c,
        Branch__r.Name
      FROM CourseOffering
      WHERE
        LearningCourseId = :courseId
        AND Class_Status__c IN ('Planned', 'Open', 'Full', 'In Progress')
        AND (EndDate = NULL
        OR EndDate > :now)
        AND Branch__c != NULL
      WITH USER_MODE
      ORDER BY StartDate
      LIMIT 5
    ]) {
      List<String> times = new List<String>();
      for (CourseOfferingSchedule s : [
        SELECT Description
        FROM CourseOfferingSchedule
        WHERE CourseOfferingId = :c.Id
        WITH USER_MODE
        LIMIT 2
      ]) {
        if (String.isNotBlank(s.Description)) {
          times.add(s.Description);
        }
      }
      lines.add(
        join(
          new List<String>{
            c.Name,
            c.Branch__r?.Name,
            c.StartDate == null
              ? null
              : 'starts ' + c.StartDate.date().format(),
            times.isEmpty() ? null : String.join(times, ', '),
            c.Delivery_Mode__c,
            c.Class_Status__c == 'Full'
              ? 'full (waitlist available)'
              : (c.Seats_Available__c == null
                  ? null
                  : c.Seats_Available__c + ' seats left')
          }
        )
      );
    }
    return lines.isEmpty()
      ? 'no classes scheduled yet; offer to add them to the interest list'
      : String.join(lines, '\n');
  }

  // ---------------------------------------------------------------- F4.3 progress and comments

  /** Parent-friendly progress summary of a learner (person account). */
  public static AiService.Result learnerProgress(Id learnerAccountId) {
    Account learner = [
      SELECT Id, FirstName, PersonContactId, Branch__c
      FROM Account
      WHERE Id = :learnerAccountId
      WITH USER_MODE
    ];
    Map<String, String> v = new Map<String, String>{
      'LearnerName' => learner.FirstName,
      'Classes' => learnerClasses(learner.PersonContactId),
      'Results' => recentResults(learner.PersonContactId),
      'AuthorName' => UserInfo.getFirstName()
    };
    return AiService.generateOrFail(
      'Learner_Progress_Summary',
      v,
      learner.Id,
      learner.Branch__c
    );
  }

  /** Report-card comment draft for one enrolment. */
  public static AiService.Result reportComment(Id enrolmentId) {
    CourseOfferingParticipant e = [
      SELECT
        Id,
        Branch__c,
        ParticipantContactId,
        ParticipantContact.FirstName,
        CourseOffering.Name,
        CourseOffering.LearningCourse.Name,
        Attendance_Rate__c,
        Sessions_Missed__c,
        Course_Score__c,
        Course_Grade__c
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
      WITH USER_MODE
    ];
    Map<String, String> v = new Map<String, String>{
      'LearnerName' => e.ParticipantContact?.FirstName,
      'Course' => e.CourseOffering?.LearningCourse?.Name,
      'ClassName' => e.CourseOffering?.Name,
      'Attendance' => e.Attendance_Rate__c == null
        ? 'not recorded'
        : e.Attendance_Rate__c.setScale(0) + '%',
      'SessionsMissed' => String.valueOf(
        e.Sessions_Missed__c == null ? 0 : e.Sessions_Missed__c
      ),
      'CourseScore' => e.Course_Score__c == null
        ? 'not yet graded'
        : e.Course_Score__c.setScale(1) + '%',
      'Grade' => firstNonBlank(e.Course_Grade__c, 'not yet graded'),
      'Results' => recentResults(e.ParticipantContactId)
    };
    return AiService.generateOrFail('Report_Comment', v, e.Id, e.Branch__c);
  }

  private static String learnerClasses(Id learnerContactId) {
    List<String> lines = new List<String>();
    for (CourseOfferingParticipant e : [
      SELECT
        CourseOffering.Name,
        ParticipationStatus,
        Attendance_Rate__c,
        Sessions_Missed__c,
        Course_Score__c,
        Course_Grade__c,
        Grade_Status__c,
        Risk_Level__c,
        Risk_Reasons__c
      FROM CourseOfferingParticipant
      WHERE
        ParticipantContactId = :learnerContactId
        AND ParticipationStatus IN ('Enrolled', 'On Hold', 'Completed')
      WITH USER_MODE
      LIMIT 10
    ]) {
      lines.add(
        join(
          new List<String>{
            e.CourseOffering?.Name,
            e.ParticipationStatus,
            e.Attendance_Rate__c == null
              ? null
              : 'attendance ' + e.Attendance_Rate__c.setScale(0) + '%',
            e.Sessions_Missed__c == null ||
              e.Sessions_Missed__c == 0
              ? null
              : e.Sessions_Missed__c + ' sessions missed',
            e.Course_Score__c == null
              ? null
              : 'course score ' + e.Course_Score__c.setScale(1) + '%',
            e.Course_Grade__c == null
              ? null
              : 'grade ' +
                e.Course_Grade__c +
                (e.Grade_Status__c == 'Final' ? ' (final)' : ' (provisional)'),
            e.Risk_Level__c == 'High' ||
              e.Risk_Level__c == 'Medium'
              ? 'needs support: ' + e.Risk_Reasons__c
              : null
          }
        )
      );
    }
    return lines.isEmpty() ? 'no current classes' : String.join(lines, '\n');
  }

  private static String recentResults(Id learnerContactId) {
    List<String> lines = new List<String>();
    for (Assessment_Result__c r : [
      SELECT
        Course_Assessment__r.Name,
        Course_Assessment__r.Assessment_Type__c,
        Percentage__c,
        Grade__c,
        Absent__c,
        Feedback__c
      FROM Assessment_Result__c
      WHERE Learner__c = :learnerContactId AND Status__c = 'Published'
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 8
    ]) {
      lines.add(
        join(
          new List<String>{
            r.Course_Assessment__r?.Name,
            r.Course_Assessment__r?.Assessment_Type__c,
            r.Absent__c
              ? 'absent'
              : (r.Percentage__c == null
                  ? null
                  : r.Percentage__c.setScale(0) + '%'),
            r.Grade__c,
            r.Feedback__c == null ? null : 'teacher note: ' + r.Feedback__c
          }
        )
      );
    }
    return lines.isEmpty()
      ? 'no published results yet'
      : String.join(lines, '\n');
  }

  public class CommentLearner {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public String comment;
  }

  /** Learners of a class with their current report-card comment. */
  public static List<CommentLearner> classLearners(Id offeringId) {
    List<CommentLearner> rows = new List<CommentLearner>();
    for (CourseOfferingParticipant e : [
      SELECT Id, ParticipantContact.Name, Course_Grade__c, Report_Comment__c
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :offeringId
        AND ParticipationStatus IN ('Enrolled', 'On Hold', 'Completed')
      WITH USER_MODE
      ORDER BY ParticipantContact.LastName
      LIMIT 100
    ]) {
      CommentLearner row = new CommentLearner();
      row.enrolmentId = e.Id;
      row.learner = e.ParticipantContact?.Name;
      row.grade = e.Course_Grade__c;
      row.comment = e.Report_Comment__c;
      rows.add(row);
    }
    return rows;
  }

  /** Saves a reviewed report-card comment through the grading rules (class teacher / coordinator). */
  public static void useReportComment(
    Id enrolmentId,
    String comment,
    Id interactionId
  ) {
    CourseOfferingParticipant e = [
      SELECT CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
      WITH USER_MODE
    ];
    GradingService.CommentRow row = new GradingService.CommentRow();
    row.enrolmentId = enrolmentId;
    row.comment = comment;
    GradingService.saveComments(
      e.CourseOfferingId,
      new List<GradingService.CommentRow>{ row }
    );
    if (interactionId != null) {
      AiService.review(interactionId, 'Edited', comment, null, null);
    }
  }

  // ---------------------------------------------------------------- F4.4 record summaries

  /** Summary of a record: enquiry (Lead), application, class, branch daily brief, learner. */
  public static AiService.Result summarise(Id recordId) {
    SObjectType type = recordId.getSobjectType();
    if (type == Lead.SObjectType) {
      return summariseEnquiry(recordId);
    } else if (type == IndividualApplication.SObjectType) {
      return summariseApplication(recordId);
    } else if (type == CourseOffering.SObjectType) {
      return summariseClass(recordId);
    } else if (type == Branch__c.SObjectType) {
      return branchBrief(recordId);
    } else if (type == Account.SObjectType) {
      return learnerProgress(recordId);
    }
    throw new AppException(
      'AI summaries are not available for this kind of record.'
    );
  }

  private static AiService.Result summariseEnquiry(Id leadId) {
    Lead l = [
      SELECT
        FirstName,
        Status,
        Enquiry_Channel__c,
        CreatedDate,
        Branch__c,
        Branch__r.Name,
        Interested_Course__r.Name,
        Next_Follow_Up__c,
        Last_Contacted__c,
        Trial_Session_Date__c,
        Description,
        Possible_Duplicate__c
      FROM Lead
      WHERE Id = :leadId
      WITH USER_MODE
    ];
    List<String> activity = new List<String>();
    for (Task t : [
      SELECT Subject, Status, ActivityDate, Description
      FROM Task
      WHERE WhoId = :leadId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 8
    ]) {
      activity.add(
        join(
          new List<String>{
            t.ActivityDate == null ? null : t.ActivityDate.format(),
            t.Subject,
            t.Status,
            t.Description == null ? null : t.Description.left(200)
          }
        )
      );
    }
    Map<String, String> v = new Map<String, String>{
      'RecordType' => 'enquiry',
      'Facts' => join(
        new List<String>{
          'learner ' + l.FirstName,
          'status ' + l.Status,
          'channel ' + l.Enquiry_Channel__c,
          'received ' + l.CreatedDate.date().format(),
          'branch ' + l.Branch__r?.Name,
          'course ' + l.Interested_Course__r?.Name,
          l.Last_Contacted__c == null
            ? 'not contacted yet'
            : 'last contacted ' + l.Last_Contacted__c.format(),
          l.Next_Follow_Up__c == null
            ? null
            : 'next follow-up ' + l.Next_Follow_Up__c.format(),
          l.Trial_Session_Date__c == null
            ? null
            : 'trial session ' + l.Trial_Session_Date__c.format(),
          l.Possible_Duplicate__c ? 'possible duplicate' : null,
          l.Description == null ? null : 'notes: ' + l.Description.left(500)
        }
      ),
      'Activity' => activity.isEmpty()
        ? 'no activity logged'
        : String.join(activity, '\n')
    };
    return AiService.generateOrFail('Record_Summary', v, leadId, l.Branch__c);
  }

  private static AiService.Result summariseApplication(Id applicationId) {
    IndividualApplication a = [
      SELECT
        Name,
        Status,
        Branch__c,
        Branch__r.Name,
        Learning_Course__r.Name,
        Eligibility_Status__c,
        Eligibility_Notes__c,
        Checklist_Complete__c,
        Decision__c,
        Decision_Reason__c,
        Offer_Status__c,
        Offer_Expiry_Date__c,
        CreatedDate
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH USER_MODE
    ];
    List<String> docs = new List<String>();
    for (DocumentChecklistItem d : [
      SELECT Name, Status
      FROM DocumentChecklistItem
      WHERE ParentRecordId = :applicationId
      WITH USER_MODE
      LIMIT 20
    ]) {
      docs.add(d.Name + ': ' + d.Status);
    }
    Map<String, String> v = new Map<String, String>{
      'RecordType' => 'application',
      'Facts' => join(
        new List<String>{
          a.Name,
          'status ' + a.Status,
          'course ' + a.Learning_Course__r?.Name,
          'branch ' + a.Branch__r?.Name,
          'eligibility ' +
          a.Eligibility_Status__c +
          (a.Eligibility_Notes__c == null
            ? ''
            : ' (' + a.Eligibility_Notes__c.left(200) + ')'),
          a.Checklist_Complete__c
            ? 'documents complete'
            : 'documents incomplete',
          a.Decision__c == null
            ? 'no decision yet'
            : 'decision ' + a.Decision__c,
          a.Decision_Reason__c == null
            ? null
            : 'reason: ' + a.Decision_Reason__c.left(200),
          'offer ' +
          a.Offer_Status__c +
          (a.Offer_Expiry_Date__c == null
            ? ''
            : ' until ' + a.Offer_Expiry_Date__c.format()),
          'received ' + a.CreatedDate.date().format()
        }
      ),
      'Activity' => docs.isEmpty()
        ? 'no checklist'
        : 'checklist: ' + String.join(docs, '; ')
    };
    return AiService.generateOrFail(
      'Record_Summary',
      v,
      applicationId,
      a.Branch__c
    );
  }

  private static AiService.Result summariseClass(Id offeringId) {
    CourseOffering c = [
      SELECT
        Name,
        Class_Status__c,
        Branch__c,
        Branch__r.Name,
        EnrollmentCapacity,
        Seats_Taken__c,
        Waitlist_Count__c,
        StartDate,
        EndDate,
        Teacher_User__r.Name,
        Grading_Status__c
      FROM CourseOffering
      WHERE Id = :offeringId
      WITH USER_MODE
    ];
    List<String> learners = new List<String>();
    for (CourseOfferingParticipant e : [
      SELECT
        ParticipantContact.FirstName,
        Attendance_Rate__c,
        Course_Score__c,
        Risk_Level__c,
        Risk_Reasons__c
      FROM CourseOfferingParticipant
      WHERE
        CourseOfferingId = :offeringId
        AND ParticipationStatus IN ('Enrolled', 'On Hold')
      WITH USER_MODE
      ORDER BY Risk_Score__c DESC NULLS LAST
      LIMIT 30
    ]) {
      learners.add(
        join(
          new List<String>{
            e.ParticipantContact?.FirstName,
            e.Attendance_Rate__c == null
              ? null
              : 'attendance ' + e.Attendance_Rate__c.setScale(0) + '%',
            e.Course_Score__c == null
              ? null
              : 'score ' + e.Course_Score__c.setScale(0) + '%',
            e.Risk_Level__c == 'High' ||
              e.Risk_Level__c == 'Medium'
              ? e.Risk_Level__c + ' risk: ' + e.Risk_Reasons__c
              : null
          }
        )
      );
    }
    Datetime now = System.now();
    Integer upcoming = [
      SELECT COUNT()
      FROM Class_Session__c
      WHERE
        Course_Offering__c = :offeringId
        AND Start__c > :now
        AND Status__c = 'Scheduled'
      WITH USER_MODE
    ];
    Map<String, String> v = new Map<String, String>{
      'RecordType' => 'class',
      'Facts' => join(
        new List<String>{
          c.Name,
          'status ' + c.Class_Status__c,
          'branch ' + c.Branch__r?.Name,
          'teacher ' + c.Teacher_User__r?.Name,
          'seats ' +
          nvl(c.Seats_Taken__c) +
          ' of ' +
          nvl(c.EnrollmentCapacity),
          c.Waitlist_Count__c == null ||
            c.Waitlist_Count__c == 0
            ? null
            : c.Waitlist_Count__c + ' waiting',
          upcoming + ' sessions to come',
          'grading ' + c.Grading_Status__c
        }
      ),
      'Activity' => learners.isEmpty()
        ? 'no learners'
        : 'learners:\n' + String.join(learners, '\n')
    };
    return AiService.generateOrFail(
      'Record_Summary',
      v,
      offeringId,
      c.Branch__c
    );
  }

  /** Branch daily brief: classes, today's sessions, cover, at-risk learners, enquiries, fees. */
  public static AiService.Result branchBrief(Id branchId) {
    Branch__c b = [
      SELECT Id, Name
      FROM Branch__c
      WHERE Id = :branchId
      WITH USER_MODE
    ];
    BranchTemplateService.BranchKpi kpi;
    for (
      BranchTemplateService.BranchKpi k : BranchTemplateService.overview()
        .branches
    ) {
      if (k.branchId == branchId) {
        kpi = k;
      }
    }
    Datetime dayStart = Datetime.newInstance(
      Date.today(),
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime dayEnd = dayStart.addDays(1);
    Integer sessionsToday = [
      SELECT COUNT()
      FROM Class_Session__c
      WHERE
        Branch__c = :branchId
        AND Start__c >= :dayStart
        AND Start__c < :dayEnd
        AND Status__c = 'Scheduled'
      WITH USER_MODE
    ];
    Integer needCover = [
      SELECT COUNT()
      FROM Class_Session__c
      WHERE
        Branch__c = :branchId
        AND Needs_Cover__c = TRUE
        AND Start__c >= :dayStart
      WITH USER_MODE
    ];
    Integer highRisk = [
      SELECT COUNT()
      FROM CourseOfferingParticipant
      WHERE
        Branch__c = :branchId
        AND Risk_Level__c = 'High'
        AND ParticipationStatus IN ('Enrolled', 'On Hold')
      WITH USER_MODE
    ];
    Map<String, String> v = new Map<String, String>{
      'RecordType' => 'branch daily brief for ' +
      b.Name +
      ' on ' +
      Date.today().format(),
      'Facts' => kpi == null
        ? 'no figures available'
        : join(
            new List<String>{
              kpi.activeClasses +
              ' running classes, ' +
              kpi.plannedClasses +
              ' planned',
              'seats filled ' +
              (kpi.fillRate == null ? 'n/a' : kpi.fillRate + '%'),
              kpi.learners + ' learners',
              'attendance (30 days) ' +
              (kpi.attendanceRate == null ? 'n/a' : kpi.attendanceRate + '%'),
              kpi.waiting + ' on waitlists',
              kpi.openEnquiries + ' open enquiries',
              'outstanding fees ' +
              MessageService.money(kpi.outstanding) +
              ', overdue ' +
              MessageService.money(kpi.overdue)
            }
          ),
      'Activity' => join(
        new List<String>{
          sessionsToday + ' sessions today',
          needCover + ' sessions needing cover',
          highRisk + ' learners at high risk'
        }
      )
    };
    return AiService.generateOrFail('Branch_Brief', v, branchId, branchId);
  }

  // ---------------------------------------------------------------- F4.5 policy Q&A

  public class Answer {
    @AuraEnabled
    public String answer;
    @AuraEnabled
    public List<String> sources = new List<String>();
    @AuraEnabled
    public Boolean confident = false;
    @AuraEnabled
    public Id interactionId;
  }

  /** Answers a staff question from the knowledge base and live settings only, with sources. */
  public static Answer askPolicy(String question) {
    if (String.isBlank(question) || question.trim().length() < 5) {
      throw new AppException('Ask a question of a few words.');
    }
    List<AI_Knowledge__mdt> articles = AiKnowledge.retrieve(question, 4);
    Answer result = new Answer();
    if (articles.isEmpty()) {
      result.answer = 'I could not find this in the institution\'s policies. Please check with an administrator.';
      return result;
    }
    List<String> context = new List<String>();
    for (AI_Knowledge__mdt a : articles) {
      context.add('[' + a.MasterLabel + ']\n' + AiKnowledge.render(a.Body__c));
    }
    AiService.Result generated = AiService.generateOrFail(
      'Policy_QA',
      new Map<String, String>{
        'Question' => question.trim().left(500),
        'Knowledge' => String.join(context, '\n\n')
      },
      null,
      null
    );
    result.interactionId = generated.interactionId;
    try {
      Map<String, Object> parsed = AiJson.parseObject(generated.text);
      result.answer = (String) parsed.get('answer');
      result.confident = parsed.get('confident') == true;
      Map<String, String> known = new Map<String, String>();
      for (AI_Knowledge__mdt a : articles) {
        known.put(a.MasterLabel.toLowerCase(), a.MasterLabel);
      }
      if (parsed.get('sources') instanceof List<Object>) {
        for (Object s : (List<Object>) parsed.get('sources')) {
          // Only cite articles that were actually given to the model.
          String label = known.get(String.valueOf(s).trim().toLowerCase());
          if (label != null && !result.sources.contains(label)) {
            result.sources.add(label);
          }
        }
      }
    } catch (Exception e) {
      result.answer = generated.text;
    }
    if (result.sources.isEmpty()) {
      result.confident = false;
    }
    return result;
  }

  // ---------------------------------------------------------------- helpers

  private static String join(List<String> parts) {
    List<String> kept = new List<String>();
    for (String p : parts) {
      if (String.isNotBlank(p) && !p.endsWith(' null')) {
        kept.add(p);
      }
    }
    return String.join(kept, ', ');
  }

  private static String firstNonBlank(String a, String b) {
    return String.isNotBlank(a) ? a : b;
  }

  private static String nvl(Decimal value) {
    return value == null ? '?' : String.valueOf(value.setScale(0));
  }
}
