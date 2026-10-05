/**
 * Home page figures for staff. Every section runs in user mode and is only
 * computed when the running user can read the objects involved, so each
 * persona sees the figures relevant to them (a teacher sees today's sessions
 * and attendance, finance sees receivables, admissions sees the funnel).
 */
public with sharing class InsightsService {
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
    public String status;
    @AuraEnabled
    public Boolean attendanceMarked;
  }

  public class Insights {
    @AuraEnabled
    public String userFirstName;
    @AuraEnabled
    public Boolean showAdmissions = false;
    @AuraEnabled
    public Integer openEnquiries = 0;
    @AuraEnabled
    public Integer newEnquiriesThisWeek = 0;
    @AuraEnabled
    public Integer applicationsInReview = 0;
    @AuraEnabled
    public Integer readyForDecision = 0;
    @AuraEnabled
    public Integer offersAwaitingResponse = 0;
    @AuraEnabled
    public Boolean showClasses = false;
    @AuraEnabled
    public Decimal seatCapacity = 0;
    @AuraEnabled
    public Decimal seatsTaken = 0;
    @AuraEnabled
    public Integer activeClasses = 0;
    @AuraEnabled
    public Boolean showAttendance = false;
    @AuraEnabled
    public Decimal attendanceRate30Days;
    @AuraEnabled
    public Integer learnersBelowThreshold = 0;
    @AuraEnabled
    public List<SessionItem> todaysSessions = new List<SessionItem>();
    @AuraEnabled
    public Boolean showFinance = false;
    @AuraEnabled
    public Decimal outstanding = 0;
    @AuraEnabled
    public Decimal overdue = 0;
    @AuraEnabled
    public Decimal collectedThisMonth = 0;
    @AuraEnabled
    public Integer reconciliationExceptions = 0;
    @AuraEnabled
    public Integer discountsAwaitingApproval = 0;
    @AuraEnabled
    public Id dashboardId;
  }

  /** Test seam: lets a test exercise the controller's error handling. */
  @TestVisible
  private static Boolean simulateFailure = false;

  public static Insights load() {
    if (simulateFailure) {
      throw new AppException('Insights are temporarily unavailable.');
    }
    Insights result = new Insights();
    result.userFirstName = UserInfo.getFirstName();
    if (
      readable(Lead.SObjectType) && readable(IndividualApplication.SObjectType)
    ) {
      admissions(result);
    }
    if (readable(CourseOffering.SObjectType)) {
      classes(result);
    }
    if (readable(Class_Session__c.SObjectType)) {
      sessions(result);
    }
    if (
      readable(Session_Attendance__c.SObjectType) &&
      readable(CourseOfferingParticipant.SObjectType)
    ) {
      attendance(result);
    }
    if (
      readable(Student_Invoice__c.SObjectType) &&
      readable(Student_Payment__c.SObjectType)
    ) {
      finance(result);
    }
    if (
      FeatureManagement.checkPermission(EnrolmentService.APPROVE_PERMISSION) &&
      readable(CourseOfferingParticipant.SObjectType)
    ) {
      result.discountsAwaitingApproval = [
        SELECT COUNT()
        FROM CourseOfferingParticipant
        WHERE Discount_Approval_Status__c = 'Pending'
        WITH USER_MODE
      ];
    }
    for (Dashboard dashboard : [
      SELECT Id
      FROM Dashboard
      WHERE DeveloperName = 'KEM_Operations'
      WITH USER_MODE
      LIMIT 1
    ]) {
      result.dashboardId = dashboard.Id;
    }
    return result;
  }

  private static void admissions(Insights result) {
    result.showAdmissions = true;
    result.openEnquiries = [
      SELECT COUNT()
      FROM Lead
      WHERE IsConverted = FALSE AND Status != 'Unqualified'
      WITH USER_MODE
    ];
    Datetime weekStart = Datetime.newInstance(
      Date.today().toStartOfWeek(),
      Time.newInstance(0, 0, 0, 0)
    );
    result.newEnquiriesThisWeek = [
      SELECT COUNT()
      FROM Lead
      WHERE CreatedDate >= :weekStart
      WITH USER_MODE
    ];
    for (AggregateResult row : [
      SELECT Status status, COUNT(Id) total
      FROM IndividualApplication
      WHERE Status IN ('In Review', 'Ready For Decision')
      WITH USER_MODE
      GROUP BY Status
    ]) {
      Integer total = (Integer) row.get('total');
      if ((String) row.get('status') == 'In Review') {
        result.applicationsInReview = total;
      } else {
        result.readyForDecision = total;
      }
    }
    result.offersAwaitingResponse = [
      SELECT COUNT()
      FROM IndividualApplication
      WHERE Offer_Status__c = 'Offered'
      WITH USER_MODE
    ];
  }

  private static void classes(Insights result) {
    result.showClasses = true;
    AggregateResult row = [
      SELECT
        COUNT(Id) total,
        SUM(EnrollmentCapacity) capacity,
        SUM(Seats_Taken__c) taken
      FROM CourseOffering
      WHERE Class_Status__c IN ('Open', 'Full', 'In Progress')
      WITH USER_MODE
    ];
    result.activeClasses = (Integer) row.get('total');
    result.seatCapacity = nvl((Decimal) row.get('capacity'));
    result.seatsTaken = nvl((Decimal) row.get('taken'));
  }

  private static void sessions(Insights result) {
    Datetime dayStart = Datetime.newInstance(
      Date.today(),
      Time.newInstance(0, 0, 0, 0)
    );
    Datetime dayEnd = dayStart.addDays(1);
    Boolean mineOnly = !Schema.SObjectType.Class_Session__c.isUpdateable();
    Id me = UserInfo.getUserId();
    List<Class_Session__c> rows = mineOnly
      ? [
          SELECT
            Id,
            Course_Offering__r.Name,
            Start__c,
            End__c,
            Room__r.Name,
            Teacher_User__r.Name,
            Status__c,
            Attendance_Marked__c
          FROM Class_Session__c
          WHERE
            Start__c >= :dayStart
            AND Start__c < :dayEnd
            AND Teacher_User__c = :me
          WITH USER_MODE
          ORDER BY Start__c
          LIMIT 20
        ]
      : [
          SELECT
            Id,
            Course_Offering__r.Name,
            Start__c,
            End__c,
            Room__r.Name,
            Teacher_User__r.Name,
            Status__c,
            Attendance_Marked__c
          FROM Class_Session__c
          WHERE Start__c >= :dayStart AND Start__c < :dayEnd
          WITH USER_MODE
          ORDER BY Start__c
          LIMIT 20
        ];
    for (Class_Session__c s : rows) {
      SessionItem item = new SessionItem();
      item.id = s.Id;
      item.className = s.Course_Offering__r.Name;
      item.startAt = s.Start__c;
      item.endAt = s.End__c;
      item.room = s.Room__r.Name;
      item.teacher = s.Teacher_User__r.Name;
      item.status = s.Status__c;
      item.attendanceMarked = s.Attendance_Marked__c;
      result.todaysSessions.add(item);
    }
  }

  private static void attendance(Insights result) {
    result.showAttendance = true;
    Datetime since = System.now().addDays(-30);
    Integer attended = 0;
    Integer counted = 0;
    for (AggregateResult row : [
      SELECT Status__c status, COUNT(Id) total
      FROM Session_Attendance__c
      WHERE Class_Session__r.Start__c >= :since
      WITH USER_MODE
      GROUP BY Status__c
    ]) {
      String status = (String) row.get('status');
      Integer total = (Integer) row.get('total');
      if (status == 'Present' || status == 'Late') {
        attended += total;
        counted += total;
      } else if (status == 'Absent') {
        counted += total;
      }
    }
    result.attendanceRate30Days = counted == 0
      ? null
      : (Decimal.valueOf(attended) / counted * 100).setScale(1);
    result.learnersBelowThreshold = [
      SELECT COUNT()
      FROM CourseOfferingParticipant
      WHERE
        Below_Attendance_Threshold__c = TRUE
        AND ParticipationStatus IN :SeatService.SEAT_STATUSES
      WITH USER_MODE
    ];
  }

  private static void finance(Insights result) {
    result.showFinance = true;
    for (AggregateResult row : [
      SELECT Overdue__c overdue, SUM(Balance_Due__c) balance
      FROM Student_Invoice__c
      WHERE Status__c IN :BillingService.OPEN_STATUSES
      WITH USER_MODE
      GROUP BY Overdue__c
    ]) {
      Decimal balance = nvl((Decimal) row.get('balance'));
      result.outstanding += balance;
      if ((Boolean) row.get('overdue')) {
        result.overdue = balance;
      }
    }
    Date monthStart = Date.today().toStartOfMonth();
    result.collectedThisMonth = nvl(
      (Decimal) [
          SELECT SUM(Amount__c) total
          FROM Student_Payment__c
          WHERE
            Status__c = 'Confirmed'
            AND Method__c != :CreditService.CREDIT_METHOD
            AND Payment_Date__c >= :monthStart
          WITH USER_MODE
        ][0]
        .get('total')
    );
    result.reconciliationExceptions = [
      SELECT COUNT()
      FROM Student_Payment__c
      WHERE Reconciliation_Status__c = 'Exception' AND Status__c = 'Confirmed'
      WITH USER_MODE
    ];
  }

  private static Boolean readable(SObjectType type) {
    return type.getDescribe().isAccessible();
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
