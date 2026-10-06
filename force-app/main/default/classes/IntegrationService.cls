/**
 * Integration outbox for external systems (generic LMS and ERP).
 *
 * Business changes are recorded as Integration_Event__c rows with a JSON
 * snapshot. External systems poll them through the KEM APIs (GET events,
 * POST events/ack) or, when Education Setting <TARGET>_Push is On, receive
 * them from the hourly 'KEM Integration Sync' job at the named credential
 * KEM_<TARGET> (POST /events). Recording an event never breaks the business
 * action: failures are logged.
 */
public with sharing class IntegrationService {
  public static final String LMS = 'LMS';
  public static final String ERP = 'ERP';
  public static final String PERMISSION = 'KEM_Integration';
  public static final Integer MAX_ATTEMPTS = 5;
  private static final Integer PUSH_BATCH = 50;

  /** Test seam: switches event recording off (for example in heavy setup). */
  @TestVisible
  private static Boolean disabled = false;

  public class EventView {
    public String id;
    public String eventNumber;
    public String target;
    public String type;
    public String recordId;
    public Datetime createdAt;
    public String status;
    public Integer attempts;
    public Object payload;
  }

  public class EventPage {
    public List<EventView> events = new List<EventView>();
    public String next;
    public Boolean hasMore = false;
  }

  // ------------------------------------------------------------- recording

  public static Boolean enabled(String target) {
    return !disabled && AppSettings.getString(target + '_Outbox', 'On') == 'On';
  }

  /** Classes changed (LMS class.updated). */
  public static void classesChanged(Set<Id> offeringIds) {
    if (offeringIds.isEmpty() || !enabled(LMS)) {
      return;
    }
    List<Integration_Event__c> events = new List<Integration_Event__c>();
    for (CourseOffering offering : [
      SELECT
        Id,
        Name,
        LearningCourseId,
        LearningCourse.Name,
        LearningCourse.External_ID__c,
        Branch__c,
        Branch__r.Branch_Code__c,
        Class_Status__c,
        StartDate,
        EndDate,
        EnrollmentCapacity,
        Delivery_Mode__c,
        Teacher_User__r.Email,
        Teacher_User__r.Name
      FROM CourseOffering
      WHERE Id IN :offeringIds
      WITH SYSTEM_MODE
    ]) {
      events.add(
        event(
          LMS,
          'class.updated',
          offering.Id,
          offering.Branch__c,
          LmsService.classPayload(offering)
        )
      );
    }
    record(events);
  }

  /** Enrolments added or changed status (LMS enrolment.updated). */
  public static void enrolmentsChanged(Set<Id> enrolmentIds) {
    if (enrolmentIds.isEmpty() || !enabled(LMS)) {
      return;
    }
    List<Integration_Event__c> events = new List<Integration_Event__c>();
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        CourseOfferingId,
        Branch__c,
        ParticipationStatus,
        ParticipantContactId,
        ParticipantContact.FirstName,
        ParticipantContact.LastName,
        ParticipantContact.Email
      FROM CourseOfferingParticipant
      WHERE Id IN :enrolmentIds
      WITH SYSTEM_MODE
    ]) {
      Map<String, Object> payload = LmsService.rosterEntry(enrolment);
      payload.put('classId', enrolment.CourseOfferingId);
      events.add(
        event(
          LMS,
          'enrolment.updated',
          enrolment.Id,
          enrolment.Branch__c,
          payload
        )
      );
    }
    record(events);
  }

  /** Course grades of a class were finalised (LMS grades.finalised). */
  public static void gradesFinalised(Id offeringId) {
    if (!enabled(LMS)) {
      return;
    }
    List<Object> grades = new List<Object>();
    Id branchId;
    for (CourseOfferingParticipant enrolment : [
      SELECT
        Id,
        Branch__c,
        ParticipantContactId,
        Course_Score__c,
        Course_Grade__c,
        Grade_Status__c
      FROM CourseOfferingParticipant
      WHERE CourseOfferingId = :offeringId AND Grade_Status__c = 'Final'
      WITH SYSTEM_MODE
    ]) {
      branchId = enrolment.Branch__c;
      grades.add(
        new Map<String, Object>{
          'enrolmentId' => enrolment.Id,
          'learnerId' => enrolment.ParticipantContactId,
          'score' => enrolment.Course_Score__c,
          'grade' => enrolment.Course_Grade__c
        }
      );
    }
    record(
      new List<Integration_Event__c>{
        event(
          LMS,
          'grades.finalised',
          offeringId,
          branchId,
          new Map<String, Object>{ 'classId' => offeringId, 'grades' => grades }
        )
      }
    );
  }

  /** Finance documents for the ERP: invoice.issued, invoice.cancelled, payment.confirmed, credit_note.issued, refund.paid. */
  public static void financeDocuments(String eventType, List<SObject> records) {
    if (records.isEmpty() || !enabled(ERP)) {
      return;
    }
    List<Integration_Event__c> events = new List<Integration_Event__c>();
    for (SObject row : records) {
      Map<String, Object> payload = new Map<String, Object>{
        'id' => row.Id,
        'documentNumber' => row.get('Name'),
        'amount' => amountOf(row),
        'branchId' => row.get('Branch__c')
      };
      events.add(
        event(ERP, eventType, row.Id, (Id) row.get('Branch__c'), payload)
      );
    }
    record(events);
  }

  private static Object amountOf(SObject row) {
    Map<String, Object> fields = row.getPopulatedFieldsAsMap();
    return fields.containsKey('Total__c')
      ? fields.get('Total__c')
      : fields.get('Amount__c');
  }

  private static Integration_Event__c event(
    String target,
    String eventType,
    Id recordId,
    Id branchId,
    Object payload
  ) {
    return new Integration_Event__c(
      Target__c = target,
      Event_Type__c = eventType,
      Record_Id__c = recordId,
      Branch__c = branchId,
      Payload__c = JSON.serialize(payload, true),
      Status__c = 'Pending',
      Attempts__c = 0,
      // One event per record and type per transaction.
      Dedup_Key__c = (target +
        '|' +
        eventType +
        '|' +
        recordId +
        '|' +
        Request.getCurrent().getRequestId())
        .left(255)
    );
  }

  private static void record(List<Integration_Event__c> events) {
    if (events.isEmpty()) {
      return;
    }
    try {
      new Writer().insertAllowingDuplicates(events);
    } catch (Exception e) {
      Logger.error('IntegrationService.record', e, null);
    }
  }

  // --------------------------------------------------------------- polling

  /** Pending events of a target after the given event number, oldest first. */
  public static EventPage pending(
    String target,
    String afterNumber,
    Integer pageSize
  ) {
    assertIntegration();
    String validTarget = validTarget(target);
    Integer size = pageSize == null ||
      pageSize <= 0
      ? 200
      : Math.min(pageSize, 1000);
    String cursor = String.isBlank(afterNumber) ? '' : afterNumber.trim();
    Integer fetch = size + 1;
    List<Integration_Event__c> rows = [
      SELECT
        Id,
        Name,
        Target__c,
        Event_Type__c,
        Record_Id__c,
        CreatedDate,
        Status__c,
        Attempts__c,
        Payload__c
      FROM Integration_Event__c
      WHERE
        Target__c = :validTarget
        AND Status__c IN ('Pending', 'Failed')
        AND Name > :cursor
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :fetch
    ];
    EventPage page = new EventPage();
    for (Integer i = 0; i < rows.size() && i < size; i++) {
      page.events.add(view(rows[i]));
      page.next = rows[i].Name;
    }
    page.hasMore = rows.size() > size;
    return page;
  }

  /**
   * Marks events as processed (Delivered) or failed by the external system.
   * Returns how many were updated.
   */
  public static Integer acknowledge(
    List<String> eventNumbers,
    Boolean success,
    String error
  ) {
    assertIntegration();
    if (eventNumbers == null || eventNumbers.isEmpty()) {
      throw new AppException('List the event numbers to acknowledge.');
    }
    if (eventNumbers.size() > 1000) {
      throw new AppException('Acknowledge at most 1000 events at a time.');
    }
    List<Integration_Event__c> updates = new List<Integration_Event__c>();
    for (Integration_Event__c row : [
      SELECT Id, Attempts__c
      FROM Integration_Event__c
      WHERE Name IN :eventNumbers AND Status__c != 'Delivered'
      WITH SYSTEM_MODE
    ]) {
      updates.add(outcome(row, success != false, error));
    }
    new Writer().updateRecords(updates);
    return updates.size();
  }

  private static Integration_Event__c outcome(
    Integration_Event__c row,
    Boolean success,
    String error
  ) {
    Integer attempts =
      (row.Attempts__c == null ? 0 : row.Attempts__c.intValue()) + 1;
    return success
      ? new Integration_Event__c(
          Id = row.Id,
          Status__c = 'Delivered',
          Delivered_On__c = System.now(),
          Attempts__c = attempts,
          Last_Error__c = null
        )
      : new Integration_Event__c(
          Id = row.Id,
          Status__c = 'Failed',
          Attempts__c = attempts,
          Last_Error__c = String.isBlank(error)
            ? 'Rejected by the external system.'
            : error.left(255)
        );
  }

  private static EventView view(Integration_Event__c row) {
    EventView v = new EventView();
    v.id = row.Id;
    v.eventNumber = row.Name;
    v.target = row.Target__c;
    v.type = row.Event_Type__c;
    v.recordId = row.Record_Id__c;
    v.createdAt = row.CreatedDate;
    v.status = row.Status__c;
    v.attempts = row.Attempts__c == null ? 0 : row.Attempts__c.intValue();
    v.payload = String.isBlank(row.Payload__c)
      ? null
      : JSON.deserializeUntyped(row.Payload__c);
    return v;
  }

  // --------------------------------------------------------------- push

  /** Pushes pending events of every target whose push is On, then purges old events. */
  public class SyncJob implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
      for (String target : new List<String>{ LMS, ERP }) {
        if (AppSettings.getString(target + '_Push', 'Off') == 'On') {
          push(target);
        }
      }
      purge();
      Logger.flush();
    }
  }

  /** Sends up to 50 pending events in one POST; returns how many were delivered. */
  public static Integer push(String target) {
    List<Integration_Event__c> rows = [
      SELECT
        Id,
        Name,
        Target__c,
        Event_Type__c,
        Record_Id__c,
        CreatedDate,
        Status__c,
        Attempts__c,
        Payload__c
      FROM Integration_Event__c
      WHERE
        Target__c = :target
        AND Status__c IN ('Pending', 'Failed')
        AND Attempts__c < :MAX_ATTEMPTS
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT :PUSH_BATCH
    ];
    if (rows.isEmpty()) {
      return 0;
    }
    List<EventView> views = new List<EventView>();
    for (Integration_Event__c row : rows) {
      views.add(view(row));
    }
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:KEM_' + target + '/events');
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/json');
    request.setTimeout(30000);
    request.setBody(
      JSON.serialize(new Map<String, Object>{ 'events' => views }, true)
    );
    Boolean success;
    String error;
    try {
      HttpResponse response = new Http().send(request);
      success =
        response.getStatusCode() >= 200 &&
        response.getStatusCode() < 300;
      error = success
        ? null
        : 'HTTP ' + response.getStatusCode() + ': ' + response.getBody();
    } catch (Exception e) {
      success = false;
      error = e.getMessage();
    }
    List<Integration_Event__c> updates = new List<Integration_Event__c>();
    for (Integration_Event__c row : rows) {
      updates.add(outcome(row, success, error));
    }
    new Writer().updateRecords(updates);
    if (!success) {
      Logger.warn(
        'IntegrationService.push',
        target + ' push failed: ' + String.valueOf(error).left(200),
        null
      );
    }
    return success ? rows.size() : 0;
  }

  /** Deletes delivered events after the retention period, undelivered ones after three times as long. */
  public static Integer purge() {
    Integer days = AppSettings.getInteger('Integration_Retention_Days', 30);
    Datetime deliveredBefore = System.now().addDays(-days);
    Datetime anyBefore = System.now().addDays(-3 * days);
    List<Integration_Event__c> old = [
      SELECT Id
      FROM Integration_Event__c
      WHERE
        (Status__c = 'Delivered'
        AND CreatedDate < :deliveredBefore)
        OR CreatedDate < :anyBefore
      WITH SYSTEM_MODE
      LIMIT 5000
    ];
    new Writer().deleteRecords(old);
    return old.size();
  }

  // --------------------------------------------------------------- monitoring

  /** Pending (and failed) events per target, for the operations console. */
  public static Map<String, Integer> backlog() {
    Map<String, Integer> counts = new Map<String, Integer>{
      LMS => 0,
      ERP => 0
    };
    for (AggregateResult row : [
      SELECT Target__c target, COUNT(Id) total
      FROM Integration_Event__c
      WHERE Status__c IN ('Pending', 'Failed')
      WITH SYSTEM_MODE
      GROUP BY Target__c
    ]) {
      counts.put((String) row.get('target'), (Integer) row.get('total'));
    }
    return counts;
  }

  // --------------------------------------------------------------- helpers

  public static void assertIntegration() {
    if (
      !FeatureManagement.checkPermission(PERMISSION) &&
      !Schema.SObjectType.Integration_Event__c.isUpdateable()
    ) {
      throw new ForbiddenException(
        'This user is not allowed to use the integration APIs (KEM Integration permission).'
      );
    }
  }

  private static String validTarget(String target) {
    String value = String.isBlank(target) ? '' : target.trim().toUpperCase();
    if (value != LMS && value != ERP) {
      throw new AppException('target must be LMS or ERP.');
    }
    return value;
  }

  /** The caller lacks the KEM Integration permission (HTTP 403). */
  public class ForbiddenException extends Exception {
  }

  /** Outbox writes: the rows are system-managed and the integration user only reads them. */
  private without sharing class Writer {
    void insertAllowingDuplicates(List<Integration_Event__c> rows) {
      Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
    }
    void updateRecords(List<Integration_Event__c> rows) {
      Database.update(rows, AccessLevel.SYSTEM_MODE);
    }
    void deleteRecords(List<Integration_Event__c> rows) {
      Database.delete(rows, AccessLevel.SYSTEM_MODE);
    }
  }
}
