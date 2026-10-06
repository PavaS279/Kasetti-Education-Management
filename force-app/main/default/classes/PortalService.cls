/**
 * Learner and guardian portal data (ADR-003).
 *
 * Portal users have no sharing access to Kasetti records, so this class reads
 * without sharing, and every query is filtered by the set of learners the
 * signed-in contact is authorised for: themselves (when they are a learner)
 * plus learners linked to them through an active guardian relationship with
 * portal access. A learner ID from the browser is never trusted without that
 * check. Results are returned as DTOs, never as records, so no other field can
 * leak to the portal.
 */
public without sharing class PortalService {
  private static final Integer UPCOMING_DAYS = 14;

  @TestVisible
  private static Id viewerOverride;

  public class LearnerCard {
    @AuraEnabled
    public Id learnerContactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String studentNumber;
    @AuraEnabled
    public Boolean isSelf = false;
    @AuraEnabled
    public Integer activeClasses = 0;
    @AuraEnabled
    public Decimal attendanceRate;
    @AuraEnabled
    public Decimal balanceDue = 0;
    @AuraEnabled
    public Integer overdueInvoices = 0;
    @AuraEnabled
    public Datetime nextSessionStart;
    @AuraEnabled
    public String nextSessionClass;
  }

  public class Home {
    @AuraEnabled
    public String viewerName;
    @AuraEnabled
    public Boolean isGuardian = false;
    @AuraEnabled
    public List<LearnerCard> learners = new List<LearnerCard>();
    @AuraEnabled
    public Decimal totalDue = 0;
    @AuraEnabled
    public List<MessageItem> messages = new List<MessageItem>();
    @AuraEnabled
    public Integer unreadMessages = 0;
  }

  public class ClassItem {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String course;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String teacher;
    @AuraEnabled
    public Decimal attendanceRate;
  }

  public class SessionItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Datetime startAt;
    @AuraEnabled
    public Datetime endAt;
    @AuraEnabled
    public String room;
    @AuraEnabled
    public String teacher;
    @AuraEnabled
    public String deliveryMode;
    @AuraEnabled
    public String meetingUrl;
    @AuraEnabled
    public String status;
  }

  public class AttendanceItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Datetime sessionStart;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal minutesLate;
  }

  public class ResultItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String assessment;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String assessmentType;
    @AuraEnabled
    public Date assessmentDate;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public Decimal maxScore;
    @AuraEnabled
    public Decimal percentage;
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public Boolean absent;
    @AuraEnabled
    public String feedback;
  }

  public class InstalmentItem {
    @AuraEnabled
    public Decimal sequence;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal paid;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean overdue;
  }

  public class GradeItem {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String course;
    @AuraEnabled
    public Decimal score;
    @AuraEnabled
    public String grade;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Id reportCardVersionId;
  }

  public class DocumentItem {
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Datetime createdDate;
  }

  public class WaitlistItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer position;
    @AuraEnabled
    public Datetime offerExpires;
  }

  public class MessageItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String body;
    @AuraEnabled
    public Datetime sentOn;
    @AuraEnabled
    public Boolean read;
    @AuraEnabled
    public String learnerName;
  }

  public class DocumentFile {
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String base64;
  }

  public class InvoiceItem {
    @AuraEnabled
    public List<InstalmentItem> instalments = new List<InstalmentItem>();
    @AuraEnabled
    public String billingPeriod;
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String invoiceNumber;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Date issueDate;
    @AuraEnabled
    public Date dueDate;
    @AuraEnabled
    public Decimal total;
    @AuraEnabled
    public Decimal paid;
    @AuraEnabled
    public Decimal balance;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean overdue;
  }

  public class LearnerDetail {
    @AuraEnabled
    public LearnerCard learner;
    @AuraEnabled
    public List<ClassItem> classes = new List<ClassItem>();
    @AuraEnabled
    public List<SessionItem> upcoming = new List<SessionItem>();
    @AuraEnabled
    public List<AttendanceItem> attendance = new List<AttendanceItem>();
    @AuraEnabled
    public List<ResultItem> results = new List<ResultItem>();
    @AuraEnabled
    public List<InvoiceItem> invoices = new List<InvoiceItem>();
    @AuraEnabled
    public List<GradeItem> grades = new List<GradeItem>();
    @AuraEnabled
    public List<DocumentItem> documents = new List<DocumentItem>();
    @AuraEnabled
    public List<WaitlistItem> waitlist = new List<WaitlistItem>();
    @AuraEnabled
    public Decimal creditBalance = 0;
    /** Online payments are available (Education Setting Payment_Gateway_Mode is Test or Live). */
    @AuraEnabled
    public Boolean payOnline = false;
    @AuraEnabled
    public String paymentMode;
    @AuraEnabled
    public List<LibraryService.LoanRow> loans = new List<LibraryService.LoanRow>();
    @AuraEnabled
    public List<TransportService.TransportItem> transport = new List<TransportService.TransportItem>();
  }

  // ------------------------------------------------------------------ API

  public static Home home() {
    return homeFor(viewerContactId());
  }

  public static LearnerDetail learner(Id learnerContactId) {
    return learnerFor(viewerContactId(), learnerContactId);
  }

  /** The family's referral code and how their referrals went (F4.11). */
  public class ReferralInfo {
    @AuraEnabled
    public String code;
    @AuraEnabled
    public Integer referred = 0;
    @AuraEnabled
    public Integer joined = 0;
    @AuraEnabled
    public Decimal rewardAmount;
    @AuraEnabled
    public Boolean rewardsOn = false;
  }

  public static ReferralInfo referral(Boolean create) {
    return referralFor(viewerContactId(), create);
  }

  /** Referral details of the viewer; creates their code when asked. */
  public static ReferralInfo referralFor(Id viewerId, Boolean create) {
    Contact viewer = [
      SELECT AccountId, Account.Referral_Code__c
      FROM Contact
      WHERE Id = :viewerId
      WITH SYSTEM_MODE
    ];
    ReferralInfo info = new ReferralInfo();
    info.code = create == true
      ? ReferralService.codeForViewer(viewer.AccountId)
      : viewer.Account.Referral_Code__c;
    info.rewardsOn = ReferralService.rewardMode() != 'Off';
    info.rewardAmount = info.rewardsOn ? ReferralService.rewardAmount() : null;
    for (AggregateResult row : [
      SELECT Status__c status, COUNT(Id) total
      FROM Referral__c
      WHERE Referrer__c = :viewer.AccountId
      WITH SYSTEM_MODE
      GROUP BY Status__c
    ]) {
      Integer total = (Integer) row.get('total');
      info.referred += total;
      String status = (String) row.get('status');
      if (
        status == ReferralService.ENROLLED ||
        status == ReferralService.REWARDED
      ) {
        info.joined += total;
      }
    }
    return info;
  }

  /** Home as seen by the given contact (Apex only; the portal passes the signed-in contact). */
  public static Home homeFor(Id viewerId) {
    Contact viewer = [
      SELECT Id, FirstName, Name
      FROM Contact
      WHERE Id = :viewerId
      WITH SYSTEM_MODE
    ];
    Home result = new Home();
    result.viewerName = String.isBlank(viewer.FirstName)
      ? viewer.Name
      : viewer.FirstName;
    Set<Id> learnerIds = authorisedLearners(viewerId);
    result.isGuardian = !wards(viewerId).isEmpty();
    Map<Id, LearnerCard> cards = cards(learnerIds, viewerId);
    for (LearnerCard card : cards.values()) {
      result.learners.add(card);
      result.totalDue += card.balanceDue;
    }
    for (Message__c m : [
      SELECT
        Id,
        Subject__c,
        Body__c,
        Sent_On__c,
        CreatedDate,
        Read_On__c,
        Learner__r.Name
      FROM Message__c
      WHERE Recipient__c = :viewerId AND Channel__c = :MessageService.PORTAL
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 30
    ]) {
      MessageItem item = new MessageItem();
      item.id = m.Id;
      item.subject = m.Subject__c;
      item.body = m.Body__c;
      item.sentOn = m.Sent_On__c == null ? m.CreatedDate : m.Sent_On__c;
      item.read = m.Read_On__c != null;
      item.learnerName = m.Learner__r?.Name;
      if (!item.read) {
        result.unreadMessages++;
      }
      result.messages.add(item);
    }
    return result;
  }

  /** Marks one of the viewer's own portal messages as read. */
  public static void markMessageRead(Id messageId) {
    markMessageReadFor(viewerContactId(), messageId);
  }

  public static void markMessageReadFor(Id viewerId, Id messageId) {
    List<Message__c> rows = [
      SELECT Id, Read_On__c
      FROM Message__c
      WHERE Id = :messageId AND Recipient__c = :viewerId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Message not found.');
    }
    if (rows[0].Read_On__c == null) {
      new Writer()
        .updateRecords(
          new List<SObject>{
            new Message__c(Id = messageId, Read_On__c = System.now())
          }
        );
    }
  }

  /**
   * A document (invoice, receipt or report card) of a learner the viewer may
   * see, as base64. Portal users cannot open files on staff records directly.
   */
  public static DocumentFile downloadDocument(Id versionId) {
    return downloadDocumentFor(viewerContactId(), versionId);
  }

  public static DocumentFile downloadDocumentFor(Id viewerId, Id versionId) {
    Set<Id> allowed = new Set<Id>();
    for (DocumentItem item : documentsFor(authorisedLearners(viewerId))) {
      allowed.add(item.versionId);
    }
    if (!allowed.contains(versionId)) {
      throw new AppException('Document not found or not available to you.');
    }
    ContentVersion version = [
      SELECT Title, FileExtension, VersionData
      FROM ContentVersion
      WHERE Id = :versionId
      WITH SYSTEM_MODE
    ];
    DocumentFile file = new DocumentFile();
    file.fileName =
      version.Title.replaceAll('[^A-Za-z0-9 _-]', '').trim() +
      '.' +
      (String.isBlank(version.FileExtension) ? 'pdf' : version.FileExtension);
    file.base64 = EncodingUtil.base64Encode(version.VersionData);
    return file;
  }

  /** Learner detail as seen by the given contact, after the authorisation check. */
  public static LearnerDetail learnerFor(Id viewerId, Id learnerContactId) {
    if (!authorisedLearners(viewerId).contains(learnerContactId)) {
      throw new AppException('You do not have access to this learner.');
    }
    LearnerDetail detail = new LearnerDetail();
    detail.learner = cards(new Set<Id>{ learnerContactId }, viewerId)
      .get(learnerContactId);
    detail.paymentMode = PaymentLinkService.mode();
    detail.payOnline = detail.paymentMode != PaymentLinkService.MODE_OFF;

    Set<Id> offeringIds = new Set<Id>();
    for (CourseOfferingParticipant enrolment : enrolments(learnerContactId)) {
      ClassItem item = new ClassItem();
      item.name = enrolment.CourseOffering.Name;
      item.course = enrolment.CourseOffering.LearningCourse.Name;
      item.status = enrolment.ParticipationStatus;
      item.teacher = enrolment.CourseOffering.Teacher_User__r.Name;
      item.attendanceRate = enrolment.Attendance_Rate__c;
      detail.classes.add(item);
      if (SeatService.SEAT_STATUSES.contains(enrolment.ParticipationStatus)) {
        offeringIds.add(enrolment.CourseOfferingId);
      }
    }
    Datetime horizon = System.now().addDays(UPCOMING_DAYS);
    for (Class_Session__c s : [
      SELECT
        Id,
        Course_Offering__r.Name,
        Start__c,
        End__c,
        Room__r.Name,
        Teacher_User__r.Name,
        Delivery_Mode__c,
        Meeting_Url__c,
        Status__c
      FROM Class_Session__c
      WHERE
        Course_Offering__c IN :offeringIds
        AND End__c >= :System.now()
        AND Start__c <= :horizon
      WITH SYSTEM_MODE
      ORDER BY Start__c
      LIMIT 50
    ]) {
      SessionItem item = new SessionItem();
      item.id = s.Id;
      item.className = s.Course_Offering__r.Name;
      item.startAt = s.Start__c;
      item.endAt = s.End__c;
      item.room = s.Room__r.Name;
      item.teacher = s.Teacher_User__r.Name;
      item.deliveryMode = s.Delivery_Mode__c;
      item.meetingUrl = s.Status__c == 'Cancelled' ? null : s.Meeting_Url__c;
      item.status = s.Status__c;
      detail.upcoming.add(item);
    }
    for (Session_Attendance__c a : [
      SELECT
        Id,
        Status__c,
        Minutes_Late__c,
        Class_Session__r.Start__c,
        Class_Session__r.Course_Offering__r.Name
      FROM Session_Attendance__c
      WHERE Learner__c = :learnerContactId
      WITH SYSTEM_MODE
      ORDER BY Class_Session__r.Start__c DESC
      LIMIT 30
    ]) {
      AttendanceItem item = new AttendanceItem();
      item.id = a.Id;
      item.className = a.Class_Session__r.Course_Offering__r.Name;
      item.sessionStart = a.Class_Session__r.Start__c;
      item.status = a.Status__c;
      item.minutesLate = a.Minutes_Late__c;
      detail.attendance.add(item);
    }
    for (Assessment_Result__c r : [
      SELECT
        Id,
        Score__c,
        Max_Score__c,
        Percentage__c,
        Grade__c,
        Absent__c,
        Feedback__c,
        Course_Assessment__r.Name,
        Course_Assessment__r.Assessment_Type__c,
        Course_Assessment__r.Assessment_Date__c,
        Course_Assessment__r.Course_Offering__r.Name
      FROM Assessment_Result__c
      WHERE Learner__c = :learnerContactId AND Status__c = 'Published'
      WITH SYSTEM_MODE
      ORDER BY Course_Assessment__r.Assessment_Date__c DESC NULLS LAST
      LIMIT 100
    ]) {
      ResultItem item = new ResultItem();
      item.id = r.Id;
      item.assessment = r.Course_Assessment__r.Name;
      item.className = r.Course_Assessment__r.Course_Offering__r.Name;
      item.assessmentType = r.Course_Assessment__r.Assessment_Type__c;
      item.assessmentDate = r.Course_Assessment__r.Assessment_Date__c;
      item.score = r.Score__c;
      item.maxScore = r.Max_Score__c;
      item.percentage = r.Percentage__c;
      item.grade = r.Grade__c;
      item.absent = r.Absent__c;
      item.feedback = r.Feedback__c;
      detail.results.add(item);
    }
    for (Student_Invoice__c i : invoices(new Set<Id>{ learnerContactId })) {
      InvoiceItem item = new InvoiceItem();
      item.id = i.Id;
      item.invoiceNumber = i.Name;
      item.className = i.Enrolment__r.CourseOffering.Name;
      item.issueDate = i.Issue_Date__c;
      item.dueDate = i.Due_Date__c;
      item.total = i.Total__c;
      item.paid = i.Amount_Paid__c;
      item.balance = i.Balance_Due__c;
      item.status = i.Status__c;
      item.overdue = i.Overdue__c;
      item.billingPeriod = i.Billing_Period__c;
      for (Instalment__c inst : i.Instalments__r) {
        InstalmentItem plan = new InstalmentItem();
        plan.sequence = inst.Sequence__c;
        plan.dueDate = inst.Due_Date__c;
        plan.amount = inst.Amount__c;
        plan.paid = inst.Amount_Paid__c;
        plan.status = inst.Status__c;
        plan.overdue = inst.Overdue__c;
        item.instalments.add(plan);
      }
      detail.invoices.add(item);
    }
    detail.documents.addAll(documentsFor(new Set<Id>{ learnerContactId }));
    detail.loans = LibraryService.learnerLoans(learnerContactId);
    Set<Id> learnerAccounts = new Set<Id>();
    for (Contact c : [
      SELECT AccountId
      FROM Contact
      WHERE Id = :learnerContactId
      WITH SYSTEM_MODE
    ]) {
      learnerAccounts.add(c.AccountId);
    }
    detail.transport = TransportService.forLearners(learnerAccounts);
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        CourseOffering.Name,
        CourseOffering.LearningCourse.Name,
        Course_Score__c,
        Course_Grade__c,
        Grade_Status__c
      FROM CourseOfferingParticipant
      WHERE ParticipantContactId = :learnerContactId AND Course_Grade__c != NULL
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
    ]) {
      GradeItem grade = new GradeItem();
      grade.enrolmentId = enrolment.Id;
      grade.className = enrolment.CourseOffering.Name;
      grade.course = enrolment.CourseOffering.LearningCourse?.Name;
      grade.score = enrolment.Course_Score__c;
      grade.grade = enrolment.Course_Grade__c;
      grade.status = enrolment.Grade_Status__c;
      grade.reportCardVersionId = reportCardOf.get(enrolment.Id);
      detail.grades.add(grade);
    }
    for (Waitlist_Entry__c entry : [
      SELECT
        Id,
        Course_Offering__c,
        Course_Offering__r.Name,
        Status__c,
        Priority__c,
        Requested_On__c,
        Offer_Expires__c
      FROM Waitlist_Entry__c
      WHERE
        Learner_Contact__c = :learnerContactId
        AND Status__c IN ('Waiting', 'Offered')
      WITH SYSTEM_MODE
    ]) {
      WaitlistItem item = new WaitlistItem();
      item.id = entry.Id;
      item.className = entry.Course_Offering__r.Name;
      item.status = entry.Status__c;
      item.offerExpires = entry.Offer_Expires__c;
      if (entry.Status__c == 'Waiting') {
        item.position =
          [
            SELECT COUNT()
            FROM Waitlist_Entry__c
            WHERE
              Course_Offering__c = :entry.Course_Offering__c
              AND Status__c = 'Waiting'
              AND (Priority__c > :entry.Priority__c
              OR (Priority__c = :entry.Priority__c
              AND Requested_On__c < :entry.Requested_On__c))
            WITH SYSTEM_MODE
          ] + 1;
      }
      detail.waitlist.add(item);
    }
    for (AggregateResult row : [
      SELECT SUM(Balance__c) total
      FROM Credit_Note__c
      WHERE
        Learner__c = :learnerContactId
        AND Status__c IN :CreditService.USABLE
      WITH SYSTEM_MODE
    ]) {
      detail.creditBalance = row.get('total') == null
        ? 0
        : (Decimal) row.get('total');
    }
    return detail;
  }

  /** Current KEM documents (not superseded) belonging to the learners. */
  private static List<DocumentItem> documentsFor(Set<Id> learnerIds) {
    List<DocumentItem> result = new List<DocumentItem>();
    reportCardOf = new Map<Id, Id>();
    if (learnerIds.isEmpty()) {
      return result;
    }
    Set<Id> recordIds = new Set<Id>();
    for (Student_Invoice__c i : invoices(learnerIds)) {
      recordIds.add(i.Id);
    }
    for (Student_Payment__c p : [
      SELECT Id
      FROM Student_Payment__c
      WHERE
        Learner__c IN :learnerIds
        AND Status__c = 'Confirmed'
        AND Method__c != :CreditService.CREDIT_METHOD
      WITH SYSTEM_MODE
      LIMIT 200
    ]) {
      recordIds.add(p.Id);
    }
    for (CourseOfferingParticipant e : [
      SELECT Id
      FROM CourseOfferingParticipant
      WHERE ParticipantContactId IN :learnerIds
      WITH SYSTEM_MODE
    ]) {
      recordIds.add(e.Id);
    }
    // Offer letters are filed on the learner's admissions application.
    for (IndividualApplication application : [
      SELECT Id
      FROM IndividualApplication
      WHERE ContactId IN :learnerIds
      WITH SYSTEM_MODE
      LIMIT 100
    ]) {
      recordIds.add(application.Id);
    }
    // Hall tickets (F4.10) are filed on the exam candidate.
    for (Exam_Candidate__c c : [
      SELECT Id
      FROM Exam_Candidate__c
      WHERE
        Learner_Account__r.PersonContactId IN :learnerIds
        AND Status__c = 'Ticket Issued'
      WITH SYSTEM_MODE
      LIMIT 100
    ]) {
      recordIds.add(c.Id);
    }
    if (recordIds.isEmpty()) {
      return result;
    }
    for (ContentDocumentLink link : [
      SELECT
        LinkedEntityId,
        ContentDocument.Title,
        ContentDocument.CreatedDate,
        ContentDocument.LatestPublishedVersionId,
        ContentDocument.LatestPublishedVersion.Description
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :recordIds
      WITH SYSTEM_MODE
      ORDER BY ContentDocument.CreatedDate DESC
    ]) {
      String description = link.ContentDocument.LatestPublishedVersion.Description;
      if (
        description == null ||
        !description.startsWith('KEM ') ||
        description.contains('(superseded)')
      ) {
        continue;
      }
      DocumentItem item = new DocumentItem();
      item.versionId = link.ContentDocument.LatestPublishedVersionId;
      item.title = link.ContentDocument.Title;
      item.kind = description.removeStart('KEM ');
      item.createdDate = link.ContentDocument.CreatedDate;
      result.add(item);
      if (item.kind == DocumentService.REPORT_CARD) {
        reportCardOf.put(link.LinkedEntityId, item.versionId);
      }
    }
    return result;
  }

  /** Report card version per enrolment, filled by documentsFor(). */
  private static Map<Id, Id> reportCardOf = new Map<Id, Id>();

  /**
   * Learners the contact may see: themselves when they are a learner, plus
   * learners they are an active guardian of with portal access.
   */
  public static Set<Id> authorisedLearners(Id viewerContactId) {
    Set<Id> result = wards(viewerContactId);
    Contact viewer = [
      SELECT Account.KEM_Role__c
      FROM Contact
      WHERE Id = :viewerContactId
      WITH SYSTEM_MODE
    ];
    Boolean isLearner =
      viewer.Account?.KEM_Role__c == 'Learner' ||
      viewer.Account?.KEM_Role__c == 'Learner and Guardian' ||
      [
        SELECT COUNT()
        FROM CourseOfferingParticipant
        WHERE
          ParticipantContactId = :viewerContactId
          AND ParticipantAffiliation = 'Student'
        WITH SYSTEM_MODE
      ] > 0;
    if (isLearner) {
      result.add(viewerContactId);
    }
    return result;
  }

  // --------------------------------------------------------------- helpers

  /** Learners the contact is an active guardian of, with portal access granted. */
  private static Set<Id> wards(Id guardianContactId) {
    Set<Id> learnerIds = new Set<Id>();
    for (ContactContactRelation rel : [
      SELECT RelatedContactId
      FROM ContactContactRelation
      WHERE
        ContactId = :guardianContactId
        AND PartyRoleRelation.RoleName = :GuardianRelationshipService.GUARDIAN_ROLE
        AND IsActive = TRUE
        AND Portal_Access__c = TRUE
      WITH SYSTEM_MODE
    ]) {
      learnerIds.add(rel.RelatedContactId);
    }
    return learnerIds;
  }

  @TestVisible
  /** Contact of the signed-in portal user. */
  public static Id viewerContactId() {
    if (Test.isRunningTest() && viewerOverride != null) {
      return viewerOverride;
    }
    Id contactId = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ]
    .ContactId;
    if (contactId == null) {
      throw new AppException(
        'This page is for learners and guardians signed in to the portal.'
      );
    }
    return contactId;
  }

  private static Map<Id, LearnerCard> cards(Set<Id> learnerIds, Id viewerId) {
    Map<Id, LearnerCard> cards = new Map<Id, LearnerCard>();
    if (learnerIds.isEmpty()) {
      return cards;
    }
    for (Contact learner : [
      SELECT Id, Name
      FROM Contact
      WHERE Id IN :learnerIds
      WITH SYSTEM_MODE
      ORDER BY Name
    ]) {
      LearnerCard card = new LearnerCard();
      card.learnerContactId = learner.Id;
      card.name = learner.Name;
      card.isSelf = learner.Id == viewerId;
      cards.put(learner.Id, card);
    }
    for (LearnerProfile profile : [
      SELECT ContactId, Student_Number__c
      FROM LearnerProfile
      WHERE ContactId IN :learnerIds
      WITH SYSTEM_MODE
    ]) {
      cards.get(profile.ContactId).studentNumber = profile.Student_Number__c;
    }
    Map<Id, Set<Id>> offeringsByLearner = new Map<Id, Set<Id>>();
    Map<Id, List<Decimal>> rates = new Map<Id, List<Decimal>>();
    for (CourseOfferingParticipant enrolment : [
      SELECT ParticipantContactId, CourseOfferingId, Attendance_Rate__c
      FROM CourseOfferingParticipant
      WHERE
        ParticipantContactId IN :learnerIds
        AND ParticipantAffiliation = 'Student'
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH SYSTEM_MODE
    ]) {
      LearnerCard card = cards.get(enrolment.ParticipantContactId);
      card.activeClasses++;
      if (!offeringsByLearner.containsKey(card.learnerContactId)) {
        offeringsByLearner.put(card.learnerContactId, new Set<Id>());
        rates.put(card.learnerContactId, new List<Decimal>());
      }
      offeringsByLearner.get(card.learnerContactId)
        .add(enrolment.CourseOfferingId);
      if (enrolment.Attendance_Rate__c != null) {
        rates.get(card.learnerContactId).add(enrolment.Attendance_Rate__c);
      }
    }
    Set<Id> allOfferings = new Set<Id>();
    for (Id learnerId : offeringsByLearner.keySet()) {
      allOfferings.addAll(offeringsByLearner.get(learnerId));
      List<Decimal> learnerRates = rates.get(learnerId);
      if (!learnerRates.isEmpty()) {
        Decimal sum = 0;
        for (Decimal rate : learnerRates) {
          sum += rate;
        }
        cards.get(learnerId).attendanceRate = (sum / learnerRates.size())
          .setScale(1);
      }
    }
    if (!allOfferings.isEmpty()) {
      for (Class_Session__c s : [
        SELECT Course_Offering__c, Course_Offering__r.Name, Start__c
        FROM Class_Session__c
        WHERE
          Course_Offering__c IN :allOfferings
          AND Start__c >= :System.now()
          AND Status__c = 'Scheduled'
        WITH SYSTEM_MODE
        ORDER BY Start__c
        LIMIT 200
      ]) {
        for (Id learnerId : offeringsByLearner.keySet()) {
          LearnerCard card = cards.get(learnerId);
          if (
            card.nextSessionStart == null &&
            offeringsByLearner.get(learnerId).contains(s.Course_Offering__c)
          ) {
            card.nextSessionStart = s.Start__c;
            card.nextSessionClass = s.Course_Offering__r.Name;
          }
        }
      }
    }
    for (Student_Invoice__c invoice : invoices(learnerIds)) {
      LearnerCard card = cards.get(invoice.Learner__c);
      card.balanceDue += invoice.Balance_Due__c == null
        ? 0
        : invoice.Balance_Due__c;
      if (invoice.Overdue__c) {
        card.overdueInvoices++;
      }
    }
    return cards;
  }

  private static List<CourseOfferingParticipant> enrolments(Id learnerId) {
    return [
      SELECT
        CourseOfferingId,
        CourseOffering.Name,
        CourseOffering.LearningCourse.Name,
        CourseOffering.Teacher_User__r.Name,
        ParticipationStatus,
        Attendance_Rate__c
      FROM CourseOfferingParticipant
      WHERE
        ParticipantContactId = :learnerId
        AND ParticipantAffiliation = 'Student'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
    ];
  }

  private static List<Student_Invoice__c> invoices(Set<Id> learnerIds) {
    return [
      SELECT
        Id,
        Name,
        Learner__c,
        Issue_Date__c,
        Due_Date__c,
        Total__c,
        Amount_Paid__c,
        Balance_Due__c,
        Status__c,
        Overdue__c,
        Billing_Period__c,
        Enrolment__r.CourseOffering.Name,
        (
          SELECT
            Sequence__c,
            Due_Date__c,
            Amount__c,
            Amount_Paid__c,
            Status__c,
            Overdue__c
          FROM Instalments__r
          ORDER BY Sequence__c
        )
      FROM Student_Invoice__c
      WHERE
        Learner__c IN :learnerIds
        AND Status__c IN ('Issued', 'Partially Paid', 'Paid')
      WITH SYSTEM_MODE
      ORDER BY Issue_Date__c DESC
      LIMIT 100
    ];
  }

  /** Read receipts on the viewer's own messages (checked above). */
  private without sharing class Writer {
    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
