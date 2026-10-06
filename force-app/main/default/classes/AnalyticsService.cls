/**
 * Advanced analytics for managers: revenue and collection trend, enrolment
 * flow, attendance trend, retention by enrolment cohort, receivables ageing
 * and course performance, for all branches or one.
 *
 * Every figure is an aggregate query run as the user, so each person sees
 * only the records they can see; sections the user cannot read are omitted.
 */
public with sharing class AnalyticsService {
  public static final Integer DEFAULT_MONTHS = 12;
  private static final Set<String> ACTIVE = new Set<String>{
    'Enrolled',
    'On Hold',
    'Completed'
  };

  public class MonthPoint {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal invoiced = 0;
    @AuraEnabled
    public Decimal collected = 0;
    @AuraEnabled
    public Integer newEnrolments = 0;
    @AuraEnabled
    public Integer withdrawals = 0;
    @AuraEnabled
    public Decimal attendanceRate;
    @AuraEnabled
    public Integer attendanceMarks = 0;
  }

  public class Cohort {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Integer enrolled = 0;
    @AuraEnabled
    public Integer active = 0;
    @AuraEnabled
    public Integer withdrawn = 0;
    @AuraEnabled
    public Decimal retention;
  }

  public class AgeingBucket {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal amount = 0;
    @AuraEnabled
    public Integer invoices = 0;
  }

  public class CourseRow {
    @AuraEnabled
    public String course;
    @AuraEnabled
    public Integer classes = 0;
    @AuraEnabled
    public Decimal capacity = 0;
    @AuraEnabled
    public Decimal seatsTaken = 0;
    @AuraEnabled
    public Decimal fillRate;
    @AuraEnabled
    public Decimal averageScore;
  }

  public class Dashboard {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public List<MonthPoint> months = new List<MonthPoint>();
    @AuraEnabled
    public List<Cohort> cohorts = new List<Cohort>();
    @AuraEnabled
    public List<AgeingBucket> ageing = new List<AgeingBucket>();
    @AuraEnabled
    public List<CourseRow> courses = new List<CourseRow>();
    @AuraEnabled
    public Boolean showFinance = false;
    @AuraEnabled
    public Boolean showEnrolments = false;
    @AuraEnabled
    public Boolean showAttendance = false;
    @AuraEnabled
    public Decimal invoicedTotal = 0;
    @AuraEnabled
    public Decimal collectedTotal = 0;
    @AuraEnabled
    public Decimal collectionRate;
    @AuraEnabled
    public Decimal retentionRate;
    @AuraEnabled
    public Integer newEnrolmentsTotal = 0;
    @AuraEnabled
    public Integer withdrawalsTotal = 0;
  }

  public static Dashboard dashboard(Id branchId, Integer months) {
    Integer span = months == null ||
      months < 3
      ? DEFAULT_MONTHS
      : Math.min(months, 24);
    Dashboard result = new Dashboard();
    result.branchId = branchId;
    Date start = Date.today().toStartOfMonth().addMonths(1 - span);
    Map<String, MonthPoint> byKey = new Map<String, MonthPoint>();
    for (Integer i = 0; i < span; i++) {
      Date month = start.addMonths(i);
      MonthPoint point = new MonthPoint();
      point.key = key(month.year(), month.month());
      point.label = Datetime.newInstance(month, Time.newInstance(12, 0, 0, 0))
        .format('MMM yy');
      byKey.put(point.key, point);
      result.months.add(point);
    }
    if (
      readable(Student_Invoice__c.SObjectType) &&
      readable(Student_Payment__c.SObjectType)
    ) {
      result.showFinance = true;
      revenue(result, byKey, start, branchId);
      ageing(result, branchId);
    }
    if (readable(CourseOfferingParticipant.SObjectType)) {
      result.showEnrolments = true;
      enrolments(result, byKey, start, branchId);
      cohorts(result, branchId);
    }
    if (readable(Session_Attendance__c.SObjectType)) {
      result.showAttendance = true;
      attendance(byKey, start, branchId);
    }
    if (readable(CourseOffering.SObjectType)) {
      courses(result, branchId);
    }
    return result;
  }

  private static void revenue(
    Dashboard result,
    Map<String, MonthPoint> byKey,
    Date start,
    Id branchId
  ) {
    String branchFilter = branchId == null ? '' : ' AND Branch__c = :branchId';
    Map<String, Object> binds = new Map<String, Object>{
      'start' => start,
      'branchId' => branchId,
      'creditMethod' => CreditService.CREDIT_METHOD
    };
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(Issue_Date__c) y, CALENDAR_MONTH(Issue_Date__c) m, SUM(Total__c) total ' +
          'FROM Student_Invoice__c WHERE Issue_Date__c >= :start AND Status__c IN (\'Issued\', \'Partially Paid\', \'Paid\')' +
          branchFilter +
          ' GROUP BY CALENDAR_YEAR(Issue_Date__c), CALENDAR_MONTH(Issue_Date__c)',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      MonthPoint point = byKey.get(
        key((Integer) row.get('y'), (Integer) row.get('m'))
      );
      if (point != null) {
        point.invoiced = nvl((Decimal) row.get('total'));
        result.invoicedTotal += point.invoiced;
      }
    }
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(Payment_Date__c) y, CALENDAR_MONTH(Payment_Date__c) m, SUM(Amount__c) total ' +
          'FROM Student_Payment__c WHERE Payment_Date__c >= :start AND Status__c = \'Confirmed\' ' +
          'AND Method__c != :creditMethod' +
          branchFilter +
          ' GROUP BY CALENDAR_YEAR(Payment_Date__c), CALENDAR_MONTH(Payment_Date__c)',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      MonthPoint point = byKey.get(
        key((Integer) row.get('y'), (Integer) row.get('m'))
      );
      if (point != null) {
        point.collected = nvl((Decimal) row.get('total'));
        result.collectedTotal += point.collected;
      }
    }
    result.collectionRate = rate(result.collectedTotal, result.invoicedTotal);
  }

  private static void ageing(Dashboard result, Id branchId) {
    List<String> keys = new List<String>{
      'current',
      '1-30',
      '31-60',
      '61-90',
      '90+'
    };
    List<String> labels = new List<String>{
      'Not yet due',
      '1–30 days',
      '31–60 days',
      '61–90 days',
      'Over 90 days'
    };
    Map<String, AgeingBucket> buckets = new Map<String, AgeingBucket>();
    for (Integer i = 0; i < keys.size(); i++) {
      AgeingBucket bucket = new AgeingBucket();
      bucket.key = keys[i];
      bucket.label = labels[i];
      buckets.put(bucket.key, bucket);
      result.ageing.add(bucket);
    }
    Date today = Date.today();
    String query =
      'SELECT Due_Date__c due, SUM(Balance_Due__c) balance, COUNT(Id) total FROM Student_Invoice__c ' +
      'WHERE Status__c IN :openStatuses AND Balance_Due__c > 0' +
      (branchId == null ? '' : ' AND Branch__c = :branchId') +
      ' GROUP BY Due_Date__c LIMIT 2000';
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        query,
        new Map<String, Object>{
          'openStatuses' => BillingService.OPEN_STATUSES,
          'branchId' => branchId
        },
        AccessLevel.USER_MODE
      )
    ) {
      Date due = (Date) row.get('due');
      Integer late = due == null ? 0 : due.daysBetween(today);
      String bucket = late <= 0
        ? 'current'
        : late <= 30
            ? '1-30'
            : late <= 60 ? '31-60' : late <= 90 ? '61-90' : '90+';
      buckets.get(bucket).amount += nvl((Decimal) row.get('balance'));
      buckets.get(bucket).invoices += (Integer) row.get('total');
    }
  }

  private static void enrolments(
    Dashboard result,
    Map<String, MonthPoint> byKey,
    Date start,
    Id branchId
  ) {
    Datetime since = Datetime.newInstance(start, Time.newInstance(0, 0, 0, 0));
    String branchFilter = branchId == null ? '' : ' AND Branch__c = :branchId';
    Map<String, Object> binds = new Map<String, Object>{
      'since' => since,
      'branchId' => branchId
    };
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(CreatedDate) y, CALENDAR_MONTH(CreatedDate) m, COUNT(Id) total ' +
          'FROM CourseOfferingParticipant WHERE CreatedDate >= :since' +
          branchFilter +
          ' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      MonthPoint point = byKey.get(
        key((Integer) row.get('y'), (Integer) row.get('m'))
      );
      if (point != null) {
        point.newEnrolments = (Integer) row.get('total');
        result.newEnrolmentsTotal += point.newEnrolments;
      }
    }
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(LastModifiedDate) y, CALENDAR_MONTH(LastModifiedDate) m, COUNT(Id) total ' +
          'FROM CourseOfferingParticipant WHERE LastModifiedDate >= :since AND ParticipationStatus = \'Withdrew\'' +
          branchFilter +
          ' GROUP BY CALENDAR_YEAR(LastModifiedDate), CALENDAR_MONTH(LastModifiedDate)',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      MonthPoint point = byKey.get(
        key((Integer) row.get('y'), (Integer) row.get('m'))
      );
      if (point != null) {
        point.withdrawals = (Integer) row.get('total');
        result.withdrawalsTotal += point.withdrawals;
      }
    }
  }

  /** Retention of the last six enrolment cohorts (month the enrolment was created). */
  private static void cohorts(Dashboard result, Id branchId) {
    Date start = Date.today().toStartOfMonth().addMonths(-5);
    Datetime since = Datetime.newInstance(start, Time.newInstance(0, 0, 0, 0));
    Map<String, Cohort> byKey = new Map<String, Cohort>();
    for (Integer i = 0; i < 6; i++) {
      Date month = start.addMonths(i);
      Cohort cohort = new Cohort();
      cohort.key = key(month.year(), month.month());
      cohort.label = Datetime.newInstance(month, Time.newInstance(12, 0, 0, 0))
        .format('MMM yyyy');
      byKey.put(cohort.key, cohort);
      result.cohorts.add(cohort);
    }
    Integer enrolled = 0;
    Integer retained = 0;
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(CreatedDate) y, CALENDAR_MONTH(CreatedDate) m, ParticipationStatus status, COUNT(Id) total ' +
          'FROM CourseOfferingParticipant WHERE CreatedDate >= :since' +
          (branchId == null ? '' : ' AND Branch__c = :branchId') +
          ' GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate), ParticipationStatus',
        new Map<String, Object>{ 'since' => since, 'branchId' => branchId },
        AccessLevel.USER_MODE
      )
    ) {
      Cohort cohort = byKey.get(
        key((Integer) row.get('y'), (Integer) row.get('m'))
      );
      if (cohort == null) {
        continue;
      }
      Integer total = (Integer) row.get('total');
      String status = (String) row.get('status');
      cohort.enrolled += total;
      if (ACTIVE.contains(status)) {
        cohort.active += total;
      } else if (status == 'Withdrew') {
        cohort.withdrawn += total;
      }
    }
    for (Cohort cohort : result.cohorts) {
      cohort.retention = rate(cohort.active, cohort.enrolled);
      enrolled += cohort.enrolled;
      retained += cohort.active;
    }
    result.retentionRate = rate(retained, enrolled);
  }

  private static void attendance(
    Map<String, MonthPoint> byKey,
    Date start,
    Id branchId
  ) {
    Datetime since = Datetime.newInstance(start, Time.newInstance(0, 0, 0, 0));
    Map<String, Integer[]> counts = new Map<String, Integer[]>();
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CALENDAR_YEAR(Class_Session__r.Start__c) y, CALENDAR_MONTH(Class_Session__r.Start__c) m, ' +
          'Status__c status, COUNT(Id) total FROM Session_Attendance__c ' +
          'WHERE Class_Session__r.Start__c >= :since AND Status__c IN (\'Present\', \'Late\', \'Absent\')' +
          (branchId == null
            ? ''
            : ' AND Class_Session__r.Branch__c = :branchId') +
          ' GROUP BY CALENDAR_YEAR(Class_Session__r.Start__c), CALENDAR_MONTH(Class_Session__r.Start__c), Status__c',
        new Map<String, Object>{ 'since' => since, 'branchId' => branchId },
        AccessLevel.USER_MODE
      )
    ) {
      String k = key((Integer) row.get('y'), (Integer) row.get('m'));
      if (!counts.containsKey(k)) {
        counts.put(k, new List<Integer>{ 0, 0 });
      }
      Integer total = (Integer) row.get('total');
      counts.get(k)[1] += total;
      if ((String) row.get('status') != 'Absent') {
        counts.get(k)[0] += total;
      }
    }
    for (String k : counts.keySet()) {
      MonthPoint point = byKey.get(k);
      if (point != null) {
        point.attendanceMarks = counts.get(k)[1];
        point.attendanceRate = rate(counts.get(k)[0], counts.get(k)[1]);
      }
    }
  }

  private static void courses(Dashboard result, Id branchId) {
    Map<String, CourseRow> byCourse = new Map<String, CourseRow>();
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT LearningCourse.Name course, COUNT(Id) total, SUM(EnrollmentCapacity) capacity, SUM(Seats_Taken__c) taken ' +
          'FROM CourseOffering WHERE Class_Status__c IN (\'Open\', \'Full\', \'In Progress\')' +
          (branchId == null ? '' : ' AND Branch__c = :branchId') +
          ' GROUP BY LearningCourse.Name ORDER BY LearningCourse.Name LIMIT 50',
        new Map<String, Object>{ 'branchId' => branchId },
        AccessLevel.USER_MODE
      )
    ) {
      CourseRow course = new CourseRow();
      course.course = (String) row.get('course');
      course.classes = (Integer) row.get('total');
      course.capacity = nvl((Decimal) row.get('capacity'));
      course.seatsTaken = nvl((Decimal) row.get('taken'));
      course.fillRate = rate(course.seatsTaken, course.capacity);
      byCourse.put(course.course, course);
      result.courses.add(course);
    }
    if (
      byCourse.isEmpty() || !readable(CourseOfferingParticipant.SObjectType)
    ) {
      return;
    }
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CourseOffering.LearningCourse.Name course, AVG(Course_Score__c) score FROM CourseOfferingParticipant ' +
          'WHERE Course_Score__c != null AND CourseOffering.Class_Status__c IN (\'Open\', \'Full\', \'In Progress\', \'Completed\')' +
          (branchId == null ? '' : ' AND Branch__c = :branchId') +
          ' GROUP BY CourseOffering.LearningCourse.Name',
        new Map<String, Object>{ 'branchId' => branchId },
        AccessLevel.USER_MODE
      )
    ) {
      CourseRow course = byCourse.get((String) row.get('course'));
      if (course != null && row.get('score') != null) {
        course.averageScore = ((Decimal) row.get('score')).setScale(1);
      }
    }
  }

  private static String key(Integer year, Integer month) {
    return year + '-' + String.valueOf(month).leftPad(2, '0');
  }

  private static Decimal rate(Decimal part, Decimal whole) {
    return whole == null ||
      whole == 0
      ? null
      : (nvl(part) / whole * 100).setScale(1);
  }

  private static Boolean readable(SObjectType type) {
    return type.getDescribe().isAccessible();
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
