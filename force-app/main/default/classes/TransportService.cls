/**
 * Transport (F4.9): bus and van routes of a branch, their stops in order,
 * and learners assigned to a route and stop.
 *
 * Seats are counted from active assignments. The transport fee is a
 * monthly "Transport" fee line on the learner's class enrolment at the
 * route's branch, so it is invoiced with the learner's other fees by the
 * recurring billing job from the start date, and stops (Bill Until) when
 * the assignment ends. Families see their learner's route, stop, times and
 * driver in the portal; staff can message every family on a route.
 */
public with sharing class TransportService {
  public static final String FEE_TYPE = 'Transport';
  public static final String ACTIVE = 'Active';
  public static final String ENDED = 'Ended';
  public static final Set<String> DIRECTIONS = new Set<String>{
    'Both ways',
    'Morning only',
    'Afternoon only'
  };

  public class RouteSummary {
    @AuraEnabled
    public Id routeId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String vehicle;
    @AuraEnabled
    public String driver;
    @AuraEnabled
    public String driverPhone;
    @AuraEnabled
    public String morningStart;
    @AuraEnabled
    public String afternoonStart;
    @AuraEnabled
    public Integer capacity = 0;
    @AuraEnabled
    public Integer riders = 0;
    @AuraEnabled
    public Decimal fillRate;
    @AuraEnabled
    public Decimal monthlyFee;
    @AuraEnabled
    public Integer stops = 0;
    @AuraEnabled
    public Boolean active;
  }

  public class Rider {
    @AuraEnabled
    public Id assignmentId;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learner;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Decimal monthlyFee;
    @AuraEnabled
    public String guardian;
    @AuraEnabled
    public String guardianPhone;
  }

  public class StopDetail {
    @AuraEnabled
    public Id stopId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer sequence;
    @AuraEnabled
    public String pickupTime;
    @AuraEnabled
    public String dropTime;
    @AuraEnabled
    public String landmark;
    @AuraEnabled
    public List<Rider> riders = new List<Rider>();
  }

  public class RouteDetail {
    @AuraEnabled
    public RouteSummary route;
    @AuraEnabled
    public List<StopDetail> stops = new List<StopDetail>();
    @AuraEnabled
    public Boolean canManage = false;
  }

  public class AssignRequest {
    @AuraEnabled
    public Id learnerAccountId { get; set; }
    @AuraEnabled
    public Id routeId { get; set; }
    @AuraEnabled
    public Id stopId { get; set; }
    @AuraEnabled
    public String direction { get; set; }
    @AuraEnabled
    public Date startDate { get; set; }
    @AuraEnabled
    public Boolean chargeFee { get; set; }
  }

  public class LearnerOption {
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String currentRoute;
  }

  /** What a family sees in the portal. */
  public class TransportItem {
    @AuraEnabled
    public String route;
    @AuraEnabled
    public String stop;
    @AuraEnabled
    public String direction;
    @AuraEnabled
    public String pickupTime;
    @AuraEnabled
    public String dropTime;
    @AuraEnabled
    public String vehicle;
    @AuraEnabled
    public String driver;
    @AuraEnabled
    public String driverPhone;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Decimal monthlyFee;
  }

  // ---------------------------------------------------------------- reading

  /** Routes of a branch (or all), with seats used. */
  public static List<RouteSummary> routes(Id branchId) {
    List<RouteSummary> result = new List<RouteSummary>();
    Map<String, Object> binds = new Map<String, Object>{
      'branchId' => branchId
    };
    for (
      Transport_Route__c r : (List<Transport_Route__c>) Database.queryWithBinds(
        'SELECT Id, Name, Route_Code__c, Branch__r.Name, Vehicle_Number__c, Driver_Name__c, Driver_Phone__c, ' +
          'Morning_Start__c, Afternoon_Start__c, Capacity__c, Seats_Taken__c, Monthly_Fee__c, Active__c, ' +
          '(SELECT Id FROM Stops__r WHERE Active__c = TRUE) FROM Transport_Route__c' +
          (branchId == null ? '' : ' WHERE Branch__c = :branchId') +
          ' ORDER BY Active__c DESC, Name LIMIT 200',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      result.add(summary(r));
    }
    return result;
  }

  /** A route with its stops in order and the learners at each stop (the manifest). */
  public static RouteDetail route(Id routeId) {
    List<Transport_Route__c> rows = [
      SELECT
        Id,
        Name,
        Route_Code__c,
        Branch__r.Name,
        Vehicle_Number__c,
        Driver_Name__c,
        Driver_Phone__c,
        Morning_Start__c,
        Afternoon_Start__c,
        Capacity__c,
        Seats_Taken__c,
        Monthly_Fee__c,
        Active__c,
        (
          SELECT
            Id,
            Name,
            Sequence__c,
            Pickup_Time__c,
            Drop_Time__c,
            Landmark__c
          FROM Stops__r
          WHERE Active__c = TRUE
          ORDER BY Sequence__c, Name
        )
      FROM Transport_Route__c
      WHERE Id = :routeId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Route not found.');
    }
    RouteDetail detail = new RouteDetail();
    detail.route = summary(rows[0]);
    detail.canManage = Schema.SObjectType.Transport_Assignment__c.isCreateable();
    Map<Id, StopDetail> byStop = new Map<Id, StopDetail>();
    for (Transport_Stop__c s : rows[0].Stops__r) {
      StopDetail stop = new StopDetail();
      stop.stopId = s.Id;
      stop.name = s.Name;
      stop.sequence = s.Sequence__c == null ? null : s.Sequence__c.intValue();
      stop.pickupTime = s.Pickup_Time__c;
      stop.dropTime = s.Drop_Time__c;
      stop.landmark = s.Landmark__c;
      byStop.put(s.Id, stop);
      detail.stops.add(stop);
    }
    List<Transport_Assignment__c> assignments = [
      SELECT
        Id,
        Stop__c,
        Learner_Account__c,
        Learner_Account__r.Name,
        Learner_Account__r.PersonContactId,
        Direction__c,
        Start_Date__c,
        Monthly_Fee__c
      FROM Transport_Assignment__c
      WHERE Route__c = :routeId AND Status__c = :ACTIVE
      WITH USER_MODE
      ORDER BY Learner_Account__r.Name
    ];
    Set<Id> learnerContacts = new Set<Id>();
    for (Transport_Assignment__c a : assignments) {
      learnerContacts.add(a.Learner_Account__r?.PersonContactId);
    }
    Map<Id, Contact> payers = payerContacts(learnerContacts);
    for (Transport_Assignment__c a : assignments) {
      StopDetail stop = byStop.get(a.Stop__c);
      if (stop == null) {
        continue;
      }
      Rider rider = new Rider();
      rider.assignmentId = a.Id;
      rider.learnerAccountId = a.Learner_Account__c;
      rider.learner = a.Learner_Account__r?.Name;
      rider.direction = a.Direction__c;
      rider.startDate = a.Start_Date__c;
      rider.monthlyFee = a.Monthly_Fee__c;
      Contact payer = payers.get(a.Learner_Account__r?.PersonContactId);
      if (payer != null) {
        rider.guardian = payer.Name;
        rider.guardianPhone = String.isBlank(payer.MobilePhone)
          ? payer.Phone
          : payer.MobilePhone;
      }
      stop.riders.add(rider);
    }
    return detail;
  }

  /** Learners with an active enrolment at the route's branch, for assigning. */
  public static List<LearnerOption> searchLearners(Id routeId, String term) {
    if (String.isBlank(term) || term.trim().length() < 2) {
      return new List<LearnerOption>();
    }
    Transport_Route__c route = [
      SELECT Branch__c
      FROM Transport_Route__c
      WHERE Id = :routeId
      WITH USER_MODE
    ];
    String pattern =
      '%' +
      term.trim().replace('%', '').replace('_', '\\_') +
      '%';
    Map<Id, LearnerOption> byAccount = new Map<Id, LearnerOption>();
    for (CourseOfferingParticipant e : [
      SELECT ParticipantAccountId, ParticipantAccount.Name
      FROM CourseOfferingParticipant
      WHERE
        Branch__c = :route.Branch__c
        AND ParticipationStatus IN :RetentionService.ACTIVE
        AND ParticipantAccount.Name LIKE :pattern
      WITH USER_MODE
      ORDER BY ParticipantAccount.Name
      LIMIT 50
    ]) {
      if (!byAccount.containsKey(e.ParticipantAccountId)) {
        LearnerOption option = new LearnerOption();
        option.learnerAccountId = e.ParticipantAccountId;
        option.name = e.ParticipantAccount.Name;
        byAccount.put(e.ParticipantAccountId, option);
      }
    }
    for (Transport_Assignment__c a : [
      SELECT Learner_Account__c, Route__r.Name
      FROM Transport_Assignment__c
      WHERE Learner_Account__c IN :byAccount.keySet() AND Status__c = :ACTIVE
      WITH USER_MODE
    ]) {
      byAccount.get(a.Learner_Account__c).currentRoute = a.Route__r.Name;
    }
    return byAccount.values();
  }

  /** The learner's current transport, for the portal and the learner page. */
  public static List<TransportItem> forLearners(Set<Id> learnerAccountIds) {
    List<TransportItem> result = new List<TransportItem>();
    // Called by the portal after its own access check: read in system mode.
    for (Transport_Assignment__c a : [
      SELECT
        Direction__c,
        Start_Date__c,
        Monthly_Fee__c,
        Route__r.Name,
        Route__r.Vehicle_Number__c,
        Route__r.Driver_Name__c,
        Route__r.Driver_Phone__c,
        Stop__r.Name,
        Stop__r.Pickup_Time__c,
        Stop__r.Drop_Time__c
      FROM Transport_Assignment__c
      WHERE Learner_Account__c IN :learnerAccountIds AND Status__c = :ACTIVE
      WITH SYSTEM_MODE
    ]) {
      TransportItem item = new TransportItem();
      item.route = a.Route__r.Name;
      item.stop = a.Stop__r?.Name;
      item.direction = a.Direction__c;
      item.pickupTime = a.Direction__c == 'Afternoon only'
        ? null
        : a.Stop__r?.Pickup_Time__c;
      item.dropTime = a.Direction__c == 'Morning only'
        ? null
        : a.Stop__r?.Drop_Time__c;
      item.vehicle = a.Route__r.Vehicle_Number__c;
      item.driver = a.Route__r.Driver_Name__c;
      item.driverPhone = a.Route__r.Driver_Phone__c;
      item.startDate = a.Start_Date__c;
      item.monthlyFee = a.Monthly_Fee__c;
      result.add(item);
    }
    return result;
  }

  // ---------------------------------------------------------------- changes

  /** Puts a learner on a route at a stop; adds the monthly transport fee. */
  public static Id assign(AssignRequest request) {
    assertCanManage();
    if (
      request == null ||
      request.learnerAccountId == null ||
      request.routeId == null ||
      request.stopId == null
    ) {
      throw new AppException('Choose a learner, a route and a stop.');
    }
    String direction = String.isBlank(request.direction)
      ? 'Both ways'
      : request.direction;
    if (!DIRECTIONS.contains(direction)) {
      throw new AppException(
        'Choose Both ways, Morning only or Afternoon only.'
      );
    }
    Date startDate = request.startDate == null
      ? Date.today()
      : request.startDate;
    if (startDate < Date.today()) {
      throw new AppException('The start date cannot be in the past.');
    }
    Transport_Route__c route = lockedRoute(request.routeId);
    if (!route.Active__c) {
      throw new AppException('Route ' + route.Name + ' is not active.');
    }
    List<Transport_Stop__c> stops = [
      SELECT Id, Name
      FROM Transport_Stop__c
      WHERE Id = :request.stopId AND Route__c = :route.Id AND Active__c = TRUE
      WITH USER_MODE
    ];
    if (stops.isEmpty()) {
      throw new AppException(
        'Choose an active stop of route ' + route.Name + '.'
      );
    }
    Account learner = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :request.learnerAccountId
      WITH USER_MODE
    ];
    List<Transport_Assignment__c> current = [
      SELECT Id, Route__r.Name
      FROM Transport_Assignment__c
      WHERE Learner_Account__c = :learner.Id AND Status__c = :ACTIVE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!current.isEmpty()) {
      throw new AppException(
        learner.Name +
          ' already rides ' +
          current[0].Route__r.Name +
          '. End that assignment or change the stop instead.'
      );
    }
    Integer taken = activeRiders(route.Id);
    if (taken >= route.Capacity__c) {
      throw new AppException(
        'Route ' +
          route.Name +
          ' is full (' +
          taken +
          ' of ' +
          route.Capacity__c.intValue() +
          ' seats).'
      );
    }
    Boolean charge =
      request.chargeFee != false &&
      route.Monthly_Fee__c != null &&
      route.Monthly_Fee__c > 0;
    CourseOfferingParticipant enrolment;
    if (charge) {
      enrolment = billingEnrolment(learner, route.Branch__c);
    }
    Savepoint sp = Database.setSavepoint();
    try {
      Writer writer = new Writer();
      Enrolment_Fee_Line__c line;
      if (charge) {
        line = new Enrolment_Fee_Line__c(
          Enrolment__c = enrolment.Id,
          Fee_Type__c = FEE_TYPE,
          Billing_Frequency__c = BillingService.MONTHLY,
          Description__c = ('Transport – ' +
            route.Name +
            ' (' +
            stops[0].Name +
            ')')
            .left(255),
          Unit_Amount__c = route.Monthly_Fee__c,
          Discount_Amount__c = 0,
          Tax_Rate__c = 0,
          Tax_Amount__c = 0,
          Line_Total__c = route.Monthly_Fee__c,
          Next_Bill_Date__c = startDate,
          Periods_Billed__c = 0
        );
        writer.insertRecord(line);
      }
      Transport_Assignment__c assignment = new Transport_Assignment__c(
        Route__c = route.Id,
        Stop__c = stops[0].Id,
        Learner_Account__c = learner.Id,
        Enrolment__c = enrolment?.Id,
        Fee_Line__c = line?.Id,
        Branch__c = route.Branch__c,
        Direction__c = direction,
        Start_Date__c = startDate,
        Status__c = ACTIVE,
        Monthly_Fee__c = charge ? route.Monthly_Fee__c : 0
      );
      writer.insertRecord(assignment);
      writer.updateRecord(
        new Transport_Route__c(Id = route.Id, Seats_Taken__c = taken + 1)
      );
      Logger.info(
        'TransportService',
        learner.Name + ' assigned to ' + route.Name
      );
      return assignment.Id;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  /** Moves a rider to another stop of the same route. */
  public static void changeStop(Id assignmentId, Id stopId) {
    assertCanManage();
    Transport_Assignment__c a = activeAssignment(assignmentId);
    List<Transport_Stop__c> stops = [
      SELECT Id, Name
      FROM Transport_Stop__c
      WHERE Id = :stopId AND Route__c = :a.Route__c AND Active__c = TRUE
      WITH USER_MODE
    ];
    if (stops.isEmpty()) {
      throw new AppException('Choose an active stop of the same route.');
    }
    new Writer()
      .updateRecord(
        new Transport_Assignment__c(Id = a.Id, Stop__c = stops[0].Id)
      );
  }

  /** Ends a rider's transport on a date; the fee is billed up to that date. */
  public static void endAssignment(
    Id assignmentId,
    Date endDate,
    String reason
  ) {
    assertCanManage();
    Transport_Assignment__c a = activeAssignment(assignmentId);
    Date lastDay = endDate == null ? Date.today() : endDate;
    // Ending before the start date cancels the transport: nothing is billed.
    Boolean beforeStart = lastDay < a.Start_Date__c;
    Savepoint sp = Database.setSavepoint();
    try {
      Writer writer = new Writer();
      writer.updateRecord(
        new Transport_Assignment__c(
          Id = a.Id,
          Status__c = ENDED,
          End_Date__c = lastDay,
          Notes__c = String.isBlank(reason)
            ? a.Notes__c
            : (nvl(a.Notes__c) + '\nEnded: ' + reason).trim().left(255)
        )
      );
      if (a.Fee_Line__c != null) {
        Enrolment_Fee_Line__c line = [
          SELECT Id, Next_Bill_Date__c
          FROM Enrolment_Fee_Line__c
          WHERE Id = :a.Fee_Line__c
          WITH SYSTEM_MODE
        ];
        Boolean nothingLeft =
          beforeStart ||
          line.Next_Bill_Date__c == null ||
          line.Next_Bill_Date__c > lastDay;
        writer.updateRecord(
          new Enrolment_Fee_Line__c(
            Id = line.Id,
            Bill_Until__c = lastDay,
            Invoiced__c = nothingLeft
          )
        );
      }
      Transport_Route__c route = lockedRoute(a.Route__c);
      writer.updateRecord(
        new Transport_Route__c(
          Id = route.Id,
          Seats_Taken__c = activeRiders(route.Id)
        )
      );
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  /** Sends a message (for example a delay) to the fee payer of every rider of a route. */
  public static Integer notifyRoute(Id routeId, String message) {
    assertCanManage();
    if (String.isBlank(message) || message.trim().length() < 5) {
      throw new AppException('Write the message to send.');
    }
    Transport_Route__c route = [
      SELECT Id, Name, Branch__c
      FROM Transport_Route__c
      WHERE Id = :routeId
      WITH USER_MODE
    ];
    List<Transport_Assignment__c> riders = [
      SELECT
        Id,
        Learner_Account__c,
        Learner_Account__r.Name,
        Learner_Account__r.PersonContactId
      FROM Transport_Assignment__c
      WHERE Route__c = :route.Id AND Status__c = :ACTIVE
      WITH USER_MODE
    ];
    Set<Id> learnerContacts = new Set<Id>();
    for (Transport_Assignment__c a : riders) {
      learnerContacts.add(a.Learner_Account__r.PersonContactId);
    }
    Map<Id, Id> payers = MessageService.feePayersOf(learnerContacts);
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    String stamp = String.valueOf(System.now().getTime());
    for (Transport_Assignment__c a : riders) {
      MessageService.Notice n = new MessageService.Notice();
      n.recipientId = payers.get(a.Learner_Account__r.PersonContactId);
      n.learnerContactId = a.Learner_Account__r.PersonContactId;
      n.learnerAccountId = a.Learner_Account__c;
      n.branchId = route.Branch__c;
      n.relatedId = a.Id;
      n.dedupSuffix = stamp;
      n.values.put('LearnerName', a.Learner_Account__r.Name);
      n.values.put('RouteName', route.Name);
      n.values.put('Message', message.trim().left(1000));
      notices.add(n);
    }
    return notices.isEmpty()
      ? 0
      : MessageService.notify('Transport_Notice', notices);
  }

  // ---------------------------------------------------------------- helpers

  private static void assertCanManage() {
    if (!Schema.SObjectType.Transport_Assignment__c.isCreateable()) {
      throw new AppException('You do not have permission to manage transport.');
    }
  }

  private static Transport_Route__c lockedRoute(Id routeId) {
    List<Transport_Route__c> rows = [
      SELECT Id, Name, Branch__c, Capacity__c, Monthly_Fee__c, Active__c
      FROM Transport_Route__c
      WHERE Id = :routeId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Route not found.');
    }
    // Lock the route so two assignments cannot take the last seat together.
    return [
      SELECT Id, Name, Branch__c, Capacity__c, Monthly_Fee__c, Active__c
      FROM Transport_Route__c
      WHERE Id = :routeId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
  }

  private static Integer activeRiders(Id routeId) {
    return [
      SELECT COUNT()
      FROM Transport_Assignment__c
      WHERE Route__c = :routeId AND Status__c = :ACTIVE
      WITH SYSTEM_MODE
    ];
  }

  private static Transport_Assignment__c activeAssignment(Id assignmentId) {
    List<Transport_Assignment__c> rows = [
      SELECT Id, Route__c, Fee_Line__c, Start_Date__c, Status__c, Notes__c
      FROM Transport_Assignment__c
      WHERE Id = :assignmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty() || rows[0].Status__c != ACTIVE) {
      throw new AppException('This transport assignment is not active.');
    }
    return rows[0];
  }

  /** The class enrolment the transport fee is billed with: active, at the branch, latest ending. */
  private static CourseOfferingParticipant billingEnrolment(
    Account learner,
    Id branchId
  ) {
    List<CourseOfferingParticipant> rows = [
      SELECT Id, EndDate
      FROM CourseOfferingParticipant
      WHERE
        ParticipantAccountId = :learner.Id
        AND Branch__c = :branchId
        AND ParticipationStatus = 'Enrolled'
      WITH USER_MODE
      ORDER BY EndDate DESC NULLS FIRST
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AppException(
        'The transport fee is billed with a class: ' +
          learner.Name +
          ' has no active enrolment at this branch. Enrol them first, or assign without a fee.'
      );
    }
    return rows[0];
  }

  private static Map<Id, Contact> payerContacts(Set<Id> learnerContacts) {
    Map<Id, Id> payers = MessageService.feePayersOf(learnerContacts);
    Map<Id, Contact> contacts = new Map<Id, Contact>(
      [
        SELECT Id, Name, MobilePhone, Phone
        FROM Contact
        WHERE Id IN :payers.values()
        WITH USER_MODE
      ]
    );
    Map<Id, Contact> result = new Map<Id, Contact>();
    for (Id learner : payers.keySet()) {
      result.put(learner, contacts.get(payers.get(learner)));
    }
    return result;
  }

  private static RouteSummary summary(Transport_Route__c r) {
    RouteSummary s = new RouteSummary();
    s.routeId = r.Id;
    s.name = r.Name;
    s.code = r.Route_Code__c;
    s.branch = r.Branch__r?.Name;
    s.vehicle = r.Vehicle_Number__c;
    s.driver = r.Driver_Name__c;
    s.driverPhone = r.Driver_Phone__c;
    s.morningStart = r.Morning_Start__c;
    s.afternoonStart = r.Afternoon_Start__c;
    s.capacity = r.Capacity__c == null ? 0 : r.Capacity__c.intValue();
    s.riders = r.Seats_Taken__c == null ? 0 : r.Seats_Taken__c.intValue();
    s.fillRate = s.capacity == 0
      ? null
      : (Decimal.valueOf(s.riders) / s.capacity * 100).setScale(1);
    s.monthlyFee = r.Monthly_Fee__c;
    s.stops = r.Stops__r == null ? 0 : r.Stops__r.size();
    s.active = r.Active__c;
    return s;
  }

  private static String nvl(String value) {
    return value == null ? '' : value;
  }

  /** System-mode writes of system-managed fields, after the checks above. */
  private without sharing class Writer {
    void insertRecord(SObject record) {
      Database.insert(record, AccessLevel.SYSTEM_MODE);
    }
    void updateRecord(SObject record) {
      Database.update(record, AccessLevel.SYSTEM_MODE);
    }
  }
}
