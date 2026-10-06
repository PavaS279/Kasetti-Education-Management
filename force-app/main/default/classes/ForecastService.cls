/**
 * Forecasts for planning (F4.8): new enrolments and seats, invoiced revenue
 * and collections, for all branches or one.
 *
 * Everything is read as the user (sharing and field access apply), from up
 * to 24 completed months (AnalyticsService) plus what is already known:
 * the admissions pipeline, free seats in open and planned classes, monthly
 * fees of current learners, and open invoices and instalments. The time
 * series use ForecastMath (backtested; accuracy shown). Einstein can explain
 * the figures in words (explain()), but never changes them.
 */
public with sharing class ForecastService {
  public static final Integer DEFAULT_HORIZON = 3;
  public static final Integer HISTORY_MONTHS = 24;
  private static final Set<String> OPEN_APPLICATION = new Set<String>{
    'Processing',
    'In Review',
    'Ready For Decision',
    'Application Decision'
  };
  private static final Set<String> CLOSED_APPLICATION = new Set<String>{
    'Enrolled',
    'Withdrawn',
    'Canceled',
    'Enrollment Failed'
  };

  public class Point {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal actual;
    @AuraEnabled
    public Decimal forecast;
    @AuraEnabled
    public Decimal low;
    @AuraEnabled
    public Decimal high;
    @AuraEnabled
    public Boolean isFuture = false;
  }

  public class Series {
    @AuraEnabled
    public String metric;
    @AuraEnabled
    public String method;
    @AuraEnabled
    public Decimal mape;
    @AuraEnabled
    public String accuracy;
    @AuraEnabled
    public Integer historyMonths;
    @AuraEnabled
    public List<Point> points = new List<Point>();
    @AuraEnabled
    public Decimal nextTotal = 0;
    @AuraEnabled
    public Decimal lastTotal = 0;
    @AuraEnabled
    public Decimal change;
  }

  public class PipelineRow {
    @AuraEnabled
    public String stage;
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Decimal rate;
    @AuraEnabled
    public Boolean assumed = false;
    @AuraEnabled
    public Decimal expected = 0;
  }

  public class SeatRow {
    @AuraEnabled
    public String course;
    @AuraEnabled
    public Integer classes = 0;
    @AuraEnabled
    public Decimal freeSeats = 0;
    @AuraEnabled
    public Decimal demand = 0;
    @AuraEnabled
    public Decimal gap = 0;
    @AuraEnabled
    public String status;
  }

  public class CashRow {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal dueFromOpen = 0;
    @AuraEnabled
    public Decimal committedBilling = 0;
    @AuraEnabled
    public Decimal expectedCash = 0;
  }

  public class Forecast {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public Integer horizon;
    @AuraEnabled
    public Datetime generatedOn;
    @AuraEnabled
    public Boolean showEnrolments = false;
    @AuraEnabled
    public Boolean showFinance = false;
    @AuraEnabled
    public Series enrolments;
    @AuraEnabled
    public List<PipelineRow> pipeline = new List<PipelineRow>();
    @AuraEnabled
    public Decimal pipelineExpected = 0;
    @AuraEnabled
    public List<SeatRow> seats = new List<SeatRow>();
    @AuraEnabled
    public Series revenue;
    @AuraEnabled
    public Series collections;
    @AuraEnabled
    public List<CashRow> cash = new List<CashRow>();
    @AuraEnabled
    public Decimal collectionRate;
    @AuraEnabled
    public Decimal openReceivables = 0;
    @AuraEnabled
    public List<String> notes = new List<String>();
  }

  // ---------------------------------------------------------------- forecast

  public static Forecast forecast(Id branchId, Integer horizon) {
    Integer h = horizon == null ||
      horizon < 1
      ? DEFAULT_HORIZON
      : Math.min(horizon, 6);
    Forecast result = new Forecast();
    result.branchId = branchId;
    result.horizon = h;
    result.generatedOn = System.now();
    AnalyticsService.Dashboard history = AnalyticsService.dashboard(
      branchId,
      HISTORY_MONTHS
    );
    // The current month is incomplete: forecasts start with it.
    List<AnalyticsService.MonthPoint> months = history.months.clone();
    if (!months.isEmpty()) {
      months.remove(months.size() - 1);
    }
    List<String> futureKeys = new List<String>();
    List<String> futureLabels = new List<String>();
    Date first = Date.today().toStartOfMonth();
    for (Integer i = 0; i < h; i++) {
      Date m = first.addMonths(i);
      futureKeys.add(
        m.year() + '-' + String.valueOf(m.month()).leftPad(2, '0')
      );
      futureLabels.add(
        Datetime.newInstance(m, Time.newInstance(12, 0, 0, 0)).format('MMM yy')
      );
    }
    if (history.showEnrolments) {
      result.showEnrolments = true;
      List<Decimal> values = new List<Decimal>();
      for (AnalyticsService.MonthPoint p : months) {
        values.add(p.newEnrolments);
      }
      result.enrolments = series(
        'New enrolments',
        months,
        values,
        futureKeys,
        futureLabels
      );
      pipeline(result, branchId);
      if (result.enrolments.historyMonths < ForecastMath.MIN_HISTORY) {
        fromPipeline(result.enrolments, result.pipeline);
      }
      seats(result, branchId);
    }
    if (history.showFinance) {
      result.showFinance = true;
      List<Decimal> invoiced = new List<Decimal>();
      List<Decimal> collected = new List<Decimal>();
      Decimal invoicedTotal = 0;
      Decimal collectedTotal = 0;
      for (Integer i = 0; i < months.size(); i++) {
        invoiced.add(months[i].invoiced);
        collected.add(months[i].collected);
        // Collection rate over the last 12 completed months.
        if (i >= months.size() - 12) {
          invoicedTotal += months[i].invoiced;
          collectedTotal += months[i].collected;
        }
      }
      result.revenue = series(
        'Invoiced',
        months,
        invoiced,
        futureKeys,
        futureLabels
      );
      result.collections = series(
        'Collected',
        months,
        collected,
        futureKeys,
        futureLabels
      );
      result.collectionRate = invoicedTotal == 0
        ? null
        : Math.min(100, collectedTotal / invoicedTotal * 100).setScale(1);
      cash(result, branchId, futureKeys, futureLabels);
      if (result.revenue.historyMonths < ForecastMath.MIN_HISTORY) {
        fromCommittedFees(result.revenue, result.cash);
      }
    }
    notes(result);
    return result;
  }

  private static Series series(
    String metric,
    List<AnalyticsService.MonthPoint> months,
    List<Decimal> values,
    List<String> futureKeys,
    List<String> futureLabels
  ) {
    Series s = new Series();
    s.metric = metric;
    ForecastMath.Fit fit = ForecastMath.fit(values, futureKeys.size());
    s.method = fit.method;
    s.mape = fit.mape;
    s.accuracy = ForecastMath.accuracy(fit.mape);
    s.historyMonths = fit.historyMonths;
    // Show the last 12 completed months with the forecast.
    Integer start = Math.max(0, months.size() - 12);
    for (Integer i = start; i < months.size(); i++) {
      Point p = new Point();
      p.key = months[i].key;
      p.label = months[i].label;
      p.actual = values[i];
      s.points.add(p);
    }
    for (Integer i = 0; i < futureKeys.size(); i++) {
      Point p = new Point();
      p.key = futureKeys[i];
      p.label = futureLabels[i];
      p.isFuture = true;
      p.forecast = fit.forecasts[i].setScale(0, RoundingMode.HALF_UP);
      p.low = fit.lows[i].setScale(0, RoundingMode.FLOOR);
      p.high = fit.highs[i].setScale(0, RoundingMode.CEILING);
      s.points.add(p);
      s.nextTotal += p.forecast;
    }
    Integer n = Math.min(futureKeys.size(), values.size());
    for (Integer i = values.size() - n; i < values.size(); i++) {
      s.lastTotal += values[i];
    }
    s.change = s.lastTotal == 0
      ? null
      : ((s.nextTotal - s.lastTotal) / s.lastTotal * 100).setScale(1);
    return s;
  }

  // ---------------------------------------------------------------- pipeline

  /** Admissions now in progress, each stage with its historical conversion. */
  private static void pipeline(Forecast result, Id branchId) {
    Datetime since = Datetime.newInstance(
      Date.today().addMonths(-12),
      Time.newInstance(0, 0, 0, 0)
    );
    Map<String, Object> binds = new Map<String, Object>{
      'branchId' => branchId,
      'since' => since,
      'openApp' => OPEN_APPLICATION,
      'closedApp' => CLOSED_APPLICATION
    };
    String branch = branchId == null ? '' : ' AND Branch__c = :branchId';

    Boolean leads = Lead.SObjectType.getDescribe().isAccessible();
    Boolean applications = IndividualApplication.SObjectType.getDescribe()
      .isAccessible();
    Boolean waitlists = Waitlist_Entry__c.SObjectType.getDescribe()
      .isAccessible();
    Integer openEnquiries = !leads
      ? 0
      : countOf(
          'SELECT COUNT() FROM Lead WHERE IsConverted = FALSE AND Status != \'Unqualified\'' +
          branch,
          binds
        );
    Integer converted = !leads
      ? 0
      : countOf(
          'SELECT COUNT() FROM Lead WHERE IsConverted = TRUE AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer lost = !leads
      ? 0
      : countOf(
          'SELECT COUNT() FROM Lead WHERE IsConverted = FALSE AND Status = \'Unqualified\' AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer underReview = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Status IN :openApp AND Offer_Status__c != \'Offered\'' +
          branch,
          binds
        );
    Integer offered = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Offer_Status__c = \'Offered\' AND Status IN :openApp' +
          branch,
          binds
        );
    Integer appEnrolled = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Status = \'Enrolled\' AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer appClosed = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Status IN :closedApp AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer offerAccepted = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Offer_Status__c = \'Accepted\' AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer offerClosed = !applications
      ? 0
      : countOf(
          'SELECT COUNT() FROM IndividualApplication WHERE Offer_Status__c IN (\'Accepted\', \'Declined\', \'Expired\') AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer waiting = !waitlists
      ? 0
      : countOf(
          'SELECT COUNT() FROM Waitlist_Entry__c WHERE Status__c = \'Waiting\'' +
          branch,
          binds
        );
    Integer waitEnrolled = !waitlists
      ? 0
      : countOf(
          'SELECT COUNT() FROM Waitlist_Entry__c WHERE Status__c = \'Enrolled\' AND CreatedDate >= :since' +
          branch,
          binds
        );
    Integer waitClosed = !waitlists
      ? 0
      : countOf(
          'SELECT COUNT() FROM Waitlist_Entry__c WHERE Status__c IN (\'Enrolled\', \'Declined\', \'Expired\', \'Cancelled\') AND CreatedDate >= :since' +
          branch,
          binds
        );

    Decimal applicationRate = rate(appEnrolled, appClosed, 0.7);
    if (leads) {
      result.pipeline.add(
        row(
          'Open enquiries',
          openEnquiries,
          rate(converted, converted + lost, 0.3) * applicationRate,
          converted + lost == 0 || appClosed == 0
        )
      );
    }
    if (applications) {
      result.pipeline.add(
        row(
          'Applications in review',
          underReview,
          applicationRate,
          appClosed == 0
        )
      );
      result.pipeline.add(
        row(
          'Offers awaiting a reply',
          offered,
          rate(offerAccepted, offerClosed, 0.8),
          offerClosed == 0
        )
      );
    }
    if (waitlists) {
      result.pipeline.add(
        row(
          'Waitlist',
          waiting,
          rate(waitEnrolled, waitClosed, 0.5),
          waitClosed == 0
        )
      );
    }
    for (PipelineRow r : result.pipeline) {
      result.pipelineExpected += r.expected;
    }
    result.pipelineExpected = result.pipelineExpected.setScale(1);
  }

  private static PipelineRow row(
    String stage,
    Integer count,
    Decimal rate,
    Boolean assumed
  ) {
    PipelineRow r = new PipelineRow();
    r.stage = stage;
    r.count = count;
    r.rate = (rate * 100).setScale(1);
    r.assumed = assumed;
    r.expected = (count * rate).setScale(1);
    return r;
  }

  /** Share closed successfully; the assumed rate when there is no history. */
  private static Decimal rate(
    Integer success,
    Integer closed,
    Decimal assumed
  ) {
    return closed == 0 ? assumed : Decimal.valueOf(success) / closed;
  }

  private static Integer countOf(String soql, Map<String, Object> binds) {
    return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
  }

  // ---------------------------------------------------------------- seats

  /**
   * Free seats in open and planned classes running in the horizon, against
   * the forecast new enrolments shared out by each course's recent intake.
   */
  private static void seats(Forecast result, Id branchId) {
    Date horizonEnd = Date.today().toStartOfMonth().addMonths(result.horizon);
    Map<String, Object> binds = new Map<String, Object>{
      'branchId' => branchId,
      // Class start and end are date-times.
      'horizonEnd' => Datetime.newInstance(
        horizonEnd,
        Time.newInstance(0, 0, 0, 0)
      ),
      'today' => Datetime.newInstance(
        Date.today(),
        Time.newInstance(0, 0, 0, 0)
      ),
      'since' => Datetime.newInstance(
        Date.today().addMonths(-6),
        Time.newInstance(0, 0, 0, 0)
      )
    };
    String branch = branchId == null ? '' : ' AND Branch__c = :branchId';
    Map<String, SeatRow> byCourse = new Map<String, SeatRow>();
    for (
      AggregateResult r : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT LearningCourse.Name course, COUNT(Id) total, SUM(EnrollmentCapacity) capacity, SUM(Seats_Taken__c) taken ' +
          'FROM CourseOffering WHERE Class_Status__c IN (\'Open\', \'Planned\', \'Full\') ' +
          'AND (StartDate = null OR StartDate < :horizonEnd) AND (EndDate = null OR EndDate >= :today)' +
          branch +
          ' GROUP BY LearningCourse.Name LIMIT 100',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      String course = (String) r.get('course');
      if (course == null) {
        continue;
      }
      SeatRow row = new SeatRow();
      row.course = course;
      row.classes = (Integer) r.get('total');
      Decimal capacity = r.get('capacity') == null
        ? 0
        : (Decimal) r.get('capacity');
      Decimal taken = r.get('taken') == null ? 0 : (Decimal) r.get('taken');
      row.freeSeats = Math.max(0.0, capacity - taken);
      byCourse.put(course, row);
    }
    Map<String, Decimal> intake = new Map<String, Decimal>();
    Decimal intakeTotal = 0;
    for (
      AggregateResult r : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT CourseOffering.LearningCourse.Name course, COUNT(Id) total FROM CourseOfferingParticipant ' +
          'WHERE CreatedDate >= :since' +
          branch +
          ' GROUP BY CourseOffering.LearningCourse.Name',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      String course = (String) r.get('course');
      Decimal total = (Integer) r.get('total');
      if (course != null) {
        intake.put(course, total);
        intakeTotal += total;
        if (!byCourse.containsKey(course)) {
          SeatRow row = new SeatRow();
          row.course = course;
          byCourse.put(course, row);
        }
      }
    }
    Decimal demandTotal = result.enrolments == null
      ? 0
      : result.enrolments.nextTotal;
    for (SeatRow row : byCourse.values()) {
      Decimal share = intakeTotal == 0
        ? 1.0 / byCourse.size()
        : (intake.containsKey(row.course) ? intake.get(row.course) : 0) /
          intakeTotal;
      row.demand = (demandTotal * share).setScale(1);
      row.gap = (row.freeSeats - row.demand).setScale(1);
      // Less than one expected learner is noise, not a shortfall.
      row.status = row.gap <= -1
        ? 'Short'
        : (row.demand >= 1 &&
            row.gap < Math.max(1.0, row.demand * 0.2)
            ? 'Tight'
            : 'OK');
      if (row.classes > 0 || row.demand >= 1) {
        result.seats.add(row);
      }
    }
  }

  // ---------------------------------------------------------------- cash

  /**
   * Expected cash per month: open invoice balances (or their instalments)
   * by due date, overdue ones in the current month, plus monthly fees of
   * current learners billed in the month, times the collection rate.
   */
  private static void cash(
    Forecast result,
    Id branchId,
    List<String> keys,
    List<String> labels
  ) {
    Map<String, CashRow> byKey = new Map<String, CashRow>();
    for (Integer i = 0; i < keys.size(); i++) {
      CashRow row = new CashRow();
      row.key = keys[i];
      row.label = labels[i];
      byKey.put(row.key, row);
      result.cash.add(row);
    }
    Date first = Date.today().toStartOfMonth();
    Date horizonEnd = first.addMonths(keys.size());
    Map<String, Object> binds = new Map<String, Object>{
      'branchId' => branchId,
      'open' => BillingService.OPEN_STATUSES,
      'horizonEnd' => horizonEnd,
      'active' => RetentionService.ACTIVE
    };
    String branch = branchId == null ? '' : ' AND Branch__c = :branchId';
    Set<Id> withInstalments = new Set<Id>();
    for (
      Instalment__c inst : (List<Instalment__c>) Database.queryWithBinds(
        'SELECT Student_Invoice__c, Due_Date__c, Amount__c, Amount_Paid__c FROM Instalment__c ' +
          'WHERE Status__c != \'Paid\' AND Student_Invoice__r.Status__c IN :open' +
          (branchId == null
            ? ''
            : ' AND Student_Invoice__r.Branch__c = :branchId'),
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      withInstalments.add(inst.Student_Invoice__c);
      Decimal due = nvl(inst.Amount__c) - nvl(inst.Amount_Paid__c);
      addDue(byKey, keys, inst.Due_Date__c, due, horizonEnd);
      result.openReceivables += due;
    }
    for (
      Student_Invoice__c inv : (List<Student_Invoice__c>) Database.queryWithBinds(
        'SELECT Id, Due_Date__c, Balance_Due__c FROM Student_Invoice__c ' +
          'WHERE Status__c IN :open AND Balance_Due__c > 0' +
          branch,
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      if (withInstalments.contains(inv.Id)) {
        continue;
      }
      addDue(byKey, keys, inv.Due_Date__c, inv.Balance_Due__c, horizonEnd);
      result.openReceivables += inv.Balance_Due__c;
    }
    // Monthly fees of current learners: billed each month from the next bill date.
    for (
      Enrolment_Fee_Line__c line : (List<Enrolment_Fee_Line__c>) Database.queryWithBinds(
        'SELECT Line_Total__c, Next_Bill_Date__c, Enrolment__r.CourseOffering.EndDate FROM Enrolment_Fee_Line__c ' +
          'WHERE Billing_Frequency__c = \'Monthly\' AND Next_Bill_Date__c < :horizonEnd ' +
          'AND Enrolment__r.ParticipationStatus IN :active' +
          (branchId == null ? '' : ' AND Enrolment__r.Branch__c = :branchId'),
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      Datetime classEndsAt = line.Enrolment__r?.CourseOffering?.EndDate;
      Date classEnd = classEndsAt == null ? null : classEndsAt.date();
      for (Integer i = 0; i < keys.size(); i++) {
        Date monthStart = first.addMonths(i);
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Boolean billed =
          line.Next_Bill_Date__c <= monthEnd &&
          (classEnd == null ||
          classEnd >= monthStart);
        if (billed) {
          byKey.get(keys[i]).committedBilling += nvl(line.Line_Total__c);
        }
      }
    }
    Decimal rate = result.collectionRate == null
      ? 1
      : result.collectionRate / 100;
    for (CashRow row : result.cash) {
      row.dueFromOpen = row.dueFromOpen.setScale(0);
      row.committedBilling = row.committedBilling.setScale(0);
      row.expectedCash = ((row.dueFromOpen + row.committedBilling) * rate)
        .setScale(0);
    }
    result.openReceivables = result.openReceivables.setScale(0);
  }

  private static void addDue(
    Map<String, CashRow> byKey,
    List<String> keys,
    Date due,
    Decimal amount,
    Date horizonEnd
  ) {
    if (amount == null || amount <= 0) {
      return;
    }
    Date dueOn = due == null || due < Date.today() ? Date.today() : due;
    if (dueOn >= horizonEnd) {
      return;
    }
    String key =
      dueOn.year() +
      '-' +
      String.valueOf(dueOn.month()).leftPad(2, '0');
    if (byKey.containsKey(key)) {
      byKey.get(key).dueFromOpen += amount;
    }
  }

  // ---------------------------------------------------------------- short history

  /**
   * With under six months of history the time series says little: new
   * enrolments are then forecast from the admissions pipeline (expected
   * enrolments spread over the months, earliest first; the range runs from
   * none to every pipeline item enrolling).
   */
  @TestVisible
  private static void fromPipeline(Series s, List<PipelineRow> pipeline) {
    Decimal expected = 0;
    Integer items = 0;
    for (PipelineRow r : pipeline) {
      expected += r.expected;
      items += r.count;
    }
    if (expected == 0) {
      return;
    }
    List<Point> future = new List<Point>();
    for (Point p : s.points) {
      if (p.isFuture) {
        future.add(p);
      }
    }
    Integer total = expected.round(System.RoundingMode.HALF_UP).intValue();
    Integer months = future.size();
    s.method = 'Pipeline';
    s.nextTotal = 0;
    for (Integer i = 0; i < months; i++) {
      // Earlier months get the remainder: offers and applications close first.
      Integer share = total / months + (i < Math.mod(total, months) ? 1 : 0);
      Integer ceiling = items / months + (i < Math.mod(items, months) ? 1 : 0);
      future[i].forecast = share;
      future[i].low = 0;
      future[i].high = Math.max(share, ceiling);
      s.nextTotal += share;
    }
    s.change = s.lastTotal == 0
      ? null
      : ((s.nextTotal - s.lastTotal) / s.lastTotal * 100).setScale(1);
  }

  /** With under six months of history, invoicing is forecast from the monthly fees already due to be billed. */
  @TestVisible
  private static void fromCommittedFees(Series s, List<CashRow> cash) {
    Decimal committed = 0;
    for (CashRow c : cash) {
      committed += c.committedBilling;
    }
    if (committed == 0) {
      return;
    }
    s.method = 'Committed fees';
    s.nextTotal = 0;
    Integer i = 0;
    for (Point p : s.points) {
      if (p.isFuture && i < cash.size()) {
        p.forecast = cash[i].committedBilling;
        p.low = p.forecast;
        p.high = p.forecast;
        s.nextTotal += p.forecast;
        i++;
      }
    }
    s.change = s.lastTotal == 0
      ? null
      : ((s.nextTotal - s.lastTotal) / s.lastTotal * 100).setScale(1);
  }

  // ---------------------------------------------------------------- notes

  private static void notes(Forecast f) {
    for (Series s : new List<Series>{ f.enrolments, f.revenue }) {
      if (s != null && s.mape == null) {
        String basis = s.method == 'Pipeline'
          ? 'the admissions pipeline'
          : s.method == 'Committed fees'
              ? 'the monthly fees of current learners (one-time fees of new learners come on top)'
              : 'a recent average';
        f.notes.add(
          s.metric +
            ': ' +
            s.historyMonths +
            ' completed months of history, so the forecast uses ' +
            basis +
            '; accuracy is measured once there are 6 months.'
        );
      }
    }
    for (PipelineRow r : f.pipeline) {
      if (r.assumed && r.count > 0) {
        f.notes.add(
          r.stage +
            ': no completed history yet, an assumed rate of ' +
            r.rate +
            '% is used.'
        );
      }
    }
    for (SeatRow s : f.seats) {
      if (s.status == 'Short') {
        f.notes.add(
          s.course +
            ': about ' +
            s.demand.round(RoundingMode.HALF_UP) +
            ' new learners expected but ' +
            s.freeSeats +
            ' free seats: open another class.'
        );
      }
    }
  }

  // ---------------------------------------------------------------- narrative

  /** Einstein explains the forecast in words for managers (logged and measured). */
  public static AiService.Result explain(Id branchId, Integer horizon) {
    Forecast f = forecast(branchId, horizon);
    List<String> facts = new List<String>();
    String scope = 'All branches';
    if (branchId != null) {
      scope = [SELECT Name FROM Branch__c WHERE Id = :branchId WITH USER_MODE]
      .Name;
    }
    facts.add(
      'Scope: ' +
        scope +
        '; next ' +
        f.horizon +
        ' months starting this month; amounts in ' +
        UserInfo.getDefaultCurrency() +
        '.'
    );
    if (f.enrolments != null) {
      facts.add(describe(f.enrolments));
      facts.add(
        'Admissions pipeline: about ' +
          f.pipelineExpected +
          ' enrolments expected from ' +
          pipelineText(f)
      );
      List<String> seatLines = new List<String>();
      for (SeatRow s : f.seats) {
        seatLines.add(
          s.course +
            ' ' +
            s.freeSeats +
            ' free seats vs ' +
            s.demand +
            ' expected (' +
            s.status +
            ')'
        );
      }
      facts.add(
        'Seats by course: ' +
        (seatLines.isEmpty()
          ? 'no open or planned classes'
          : String.join(seatLines, '; '))
      );
    }
    if (f.revenue != null) {
      facts.add(describe(f.revenue));
      // Expected cash below is the collections outlook.
      facts.add(
        'Collection rate (12 months): ' +
          (f.collectionRate == null ? 'unknown' : f.collectionRate + '%') +
          '; open receivables ' +
          f.openReceivables
      );
      List<String> cashLines = new List<String>();
      for (CashRow c : f.cash) {
        cashLines.add(
          c.label +
            ' expected cash ' +
            c.expectedCash +
            ' (due from open invoices ' +
            c.dueFromOpen +
            ', monthly fees ' +
            c.committedBilling +
            ')'
        );
      }
      facts.add(
        'Expected cash: ' +
          String.join(cashLines, '; ') +
          '. The first month includes balances already overdue.'
      );
    }
    facts.addAll(f.notes);
    return AiService.generateOrFail(
      'Forecast_Narrative',
      new Map<String, String>{ 'Facts' => String.join(facts, '\n') },
      branchId,
      branchId
    );
  }

  private static String describe(Series s) {
    List<String> parts = new List<String>();
    for (Point p : s.points) {
      if (p.isFuture) {
        parts.add(
          p.label + ' ' + p.forecast + ' (range ' + p.low + '–' + p.high + ')'
        );
      }
    }
    return s.metric +
      ': forecast ' +
      String.join(parts, ', ') +
      '; total ' +
      s.nextTotal +
      ' vs ' +
      s.lastTotal +
      ' in the previous ' +
      parts.size() +
      ' months; method ' +
      s.method +
      ', accuracy ' +
      s.accuracy +
      (s.mape == null ? '' : ' (backtest error ' + s.mape + '%)') +
      '.';
  }

  private static String pipelineText(Forecast f) {
    List<String> parts = new List<String>();
    for (PipelineRow r : f.pipeline) {
      parts.add(
        r.count +
          ' ' +
          r.stage.toLowerCase() +
          ' at ' +
          r.rate +
          '%' +
          (r.assumed ? ' (assumed)' : '')
      );
    }
    return String.join(parts, ', ') + '.';
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }
}
