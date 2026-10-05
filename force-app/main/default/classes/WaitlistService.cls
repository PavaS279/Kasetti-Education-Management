/**
 * Class waitlists. A learner joins when a class is full. When a seat is freed
 * (withdrawal, capacity increase, an offer declined or expired) the seat is
 * offered to the next learner — highest priority first, then first come first
 * served — and held for them (Seats_Reserved__c) until they accept, decline,
 * or the offer expires (Waitlist_Offer_Hours, default 48).
 *
 * Status and offer fields are system-managed: users act through this service,
 * which checks object access first and then writes in system mode so any
 * counsellor can work the shared queue of a class they can see.
 */
public with sharing class WaitlistService {
  public static final Set<String> ACTIVE = new Set<String>{
    'Waiting',
    'Offered'
  };
  private static final Set<String> QUEUEING_CLASS_STATUSES = new Set<String>{
    'Open',
    'Full',
    'In Progress'
  };
  /** Prevents re-entrant offering while this service updates seats. */
  private static Boolean offering = false;

  public class JoinRequest {
    @AuraEnabled
    public Id learnerAccountId { get; set; }
    @AuraEnabled
    public Id offeringId { get; set; }
    @AuraEnabled
    public Id applicationId { get; set; }
    @AuraEnabled
    public Integer priority { get; set; }
    @AuraEnabled
    public String discountCode { get; set; }
    @AuraEnabled
    public String notes { get; set; }
  }

  public class Entry {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Id learnerAccountId;
    @AuraEnabled
    public String learnerName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer position;
    @AuraEnabled
    public Integer priority;
    @AuraEnabled
    public Datetime requestedOn;
    @AuraEnabled
    public Datetime offerExpires;
    @AuraEnabled
    public String notes;
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Id offeringId;
  }

  public class Waitlist {
    @AuraEnabled
    public String className;
    @AuraEnabled
    public Integer capacity;
    @AuraEnabled
    public Integer taken;
    @AuraEnabled
    public Integer reserved;
    @AuraEnabled
    public Integer available;
    @AuraEnabled
    public String classStatus;
    @AuraEnabled
    public List<Entry> entries = new List<Entry>();
    @AuraEnabled
    public Boolean canManage;
  }

  // ----------------------------------------------------------------- actions

  public static Id join(JoinRequest request) {
    assertCanManage();
    if (
      request == null ||
      request.learnerAccountId == null ||
      request.offeringId == null
    ) {
      throw new AppException('Choose a learner and a class.');
    }
    CourseOffering offering = EnrolmentService.loadOffering(
      request.offeringId,
      true
    );
    if (!QUEUEING_CLASS_STATUSES.contains(offering.Class_Status__c)) {
      throw new AppException(
        'The class is not taking enrolments, so it has no waitlist.'
      );
    }
    Account learner = PersonAccountService.reload(
        new Set<Id>{ request.learnerAccountId }
      )
      .get(request.learnerAccountId);
    if (
      learner == null ||
      learner.PersonContactId == null ||
      !LearnerService.isLearner(learner.KEM_Role__c)
    ) {
      throw new AppException('Only learners can join a waitlist.');
    }
    if (
      [
        SELECT COUNT()
        FROM CourseOfferingParticipant
        WHERE
          CourseOfferingId = :offering.Id
          AND ParticipantAccountId = :learner.Id
          AND ParticipationStatus IN :SeatService.SEAT_STATUSES
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException('The learner is already enrolled in this class.');
    }
    if (
      [
        SELECT COUNT()
        FROM Waitlist_Entry__c
        WHERE
          Course_Offering__c = :offering.Id
          AND Learner__c = :learner.Id
          AND Status__c IN :ACTIVE
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException('The learner is already on this waitlist.');
    }
    if (freeSeats(offering) > 0 && waitingCount(offering.Id) == 0) {
      throw new AppException(
        'Seats are available in this class — enrol the learner directly.'
      );
    }
    Waitlist_Entry__c entry = new Waitlist_Entry__c(
      Course_Offering__c = offering.Id,
      Learner__c = learner.Id,
      Learner_Contact__c = learner.PersonContactId,
      Application__c = request.applicationId,
      Branch__c = offering.Branch__c,
      Status__c = 'Waiting',
      Priority__c = request.priority == null ? 0 : request.priority,
      Requested_On__c = System.now(),
      Discount_Code__c = String.isBlank(request.discountCode)
        ? null
        : request.discountCode.trim().toUpperCase(),
      Notes__c = request.notes,
      Offers_Made__c = 0
    );
    new Writer().insertRecords(new List<SObject>{ entry });
    SeatService.recalculate(new Set<Id>{ offering.Id });
    return entry.Id;
  }

  /**
   * Offers every free seat of the given classes to the next learners waiting.
   * Returns the number of offers made.
   */
  public static Integer offerNext(Set<Id> offeringIds) {
    offeringIds.remove(null);
    if (offering || offeringIds.isEmpty()) {
      return 0;
    }
    Map<Id, List<Waitlist_Entry__c>> queues = new Map<Id, List<Waitlist_Entry__c>>();
    for (Waitlist_Entry__c entry : [
      SELECT Id, Course_Offering__c, Offers_Made__c, OwnerId, Learner_Contact__c
      FROM Waitlist_Entry__c
      WHERE Course_Offering__c IN :offeringIds AND Status__c = 'Waiting'
      WITH SYSTEM_MODE
      ORDER BY Priority__c DESC NULLS LAST, Requested_On__c ASC, Name ASC
    ]) {
      if (!queues.containsKey(entry.Course_Offering__c)) {
        queues.put(entry.Course_Offering__c, new List<Waitlist_Entry__c>());
      }
      queues.get(entry.Course_Offering__c).add(entry);
    }
    if (queues.isEmpty()) {
      return 0;
    }
    Map<Id, Integer> taken = SeatService.countTaken(queues.keySet());
    Map<Id, Integer> reserved = SeatService.countReserved(
      queues.keySet(),
      null
    );
    Integer hours = AppSettings.getInteger('Waitlist_Offer_Hours', 48);
    Datetime now = System.now();
    List<Waitlist_Entry__c> offers = new List<Waitlist_Entry__c>();
    List<Task> reminders = new List<Task>();
    for (CourseOffering cls : [
      SELECT Id, Name, EnrollmentCapacity, Class_Status__c
      FROM CourseOffering
      WHERE Id IN :queues.keySet()
      WITH SYSTEM_MODE
    ]) {
      if (
        cls.EnrollmentCapacity == null ||
        !QUEUEING_CLASS_STATUSES.contains(cls.Class_Status__c)
      ) {
        continue;
      }
      Integer free =
        cls.EnrollmentCapacity -
        taken.get(cls.Id) -
        reserved.get(cls.Id);
      for (Waitlist_Entry__c entry : queues.get(cls.Id)) {
        if (free <= 0) {
          break;
        }
        Datetime expires = now.addHours(hours);
        offers.add(
          new Waitlist_Entry__c(
            Id = entry.Id,
            Status__c = 'Offered',
            Offered_On__c = now,
            Offer_Expires__c = expires,
            Offers_Made__c = (entry.Offers_Made__c == null
                ? 0
                : entry.Offers_Made__c) + 1
          )
        );
        reminders.add(
          new Task(
            OwnerId = entry.OwnerId,
            WhatId = entry.Id,
            WhoId = entry.Learner_Contact__c,
            Subject = 'Waitlist seat offered in ' + cls.Name,
            Description = 'A seat is held until ' +
              expires.format() +
              '. Record the family\'s answer on the waitlist before then.',
            ActivityDate = expires.date(),
            Priority = 'High',
            Status = 'Not Started'
          )
        );
        free--;
      }
    }
    if (offers.isEmpty()) {
      return 0;
    }
    offering = true;
    try {
      Writer writer = new Writer();
      writer.updateRecords(offers);
      writer.insertRecords(reminders);
      SeatService.recalculate(queues.keySet());
    } finally {
      offering = false;
    }
    return offers.size();
  }

  /** Family accepted: enrol with the held seat at today's price. */
  public static Id accept(Id entryId) {
    assertCanManage();
    Waitlist_Entry__c entry = load(entryId, true);
    if (entry.Status__c != 'Offered') {
      throw new AppException('Only an open seat offer can be accepted.');
    }
    if (
      entry.Offer_Expires__c != null &&
      entry.Offer_Expires__c < System.now()
    ) {
      throw new AppException(
        'The seat offer expired on ' +
          entry.Offer_Expires__c.format() +
          '. Put the learner back in the queue to wait for the next seat.'
      );
    }
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = entry.Learner__c;
    request.offeringId = entry.Course_Offering__c;
    request.discountCode = entry.Discount_Code__c;
    request.waitlistEntryId = entry.Id;
    if (entry.Application__c != null) {
      IndividualApplication application = [
        SELECT Offer_Status__c
        FROM IndividualApplication
        WHERE Id = :entry.Application__c
        WITH SYSTEM_MODE
      ];
      if (application.Offer_Status__c == 'Accepted') {
        request.applicationId = entry.Application__c;
      }
    }
    Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Waitlist_Entry__c(
            Id = entry.Id,
            Status__c = 'Enrolled',
            Enrolment__c = enrolmentId,
            Responded_On__c = System.now()
          )
        }
      );
    SeatService.recalculate(new Set<Id>{ entry.Course_Offering__c });
    return enrolmentId;
  }

  public static void decline(Id entryId, String reason) {
    close(entryId, 'Declined', new Set<String>{ 'Offered' }, reason);
  }

  public static void cancel(Id entryId, String reason) {
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for removing the learner.');
    }
    close(entryId, 'Cancelled', ACTIVE, reason);
  }

  /** Puts an expired or declined learner back in the queue at their original place. */
  public static void requeue(Id entryId) {
    assertCanManage();
    Waitlist_Entry__c entry = load(entryId, true);
    if (entry.Status__c != 'Expired' && entry.Status__c != 'Declined') {
      throw new AppException(
        'Only expired or declined offers can be put back in the queue.'
      );
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Waitlist_Entry__c(
            Id = entry.Id,
            Status__c = 'Waiting',
            Offered_On__c = null,
            Offer_Expires__c = null
          )
        }
      );
    SeatService.recalculate(new Set<Id>{ entry.Course_Offering__c });
    offerNext(new Set<Id>{ entry.Course_Offering__c });
  }

  /** Expires unanswered offers and passes their seats on. Used by WaitlistOfferJob. */
  public static Integer expireOffers() {
    List<Waitlist_Entry__c> expired = new List<Waitlist_Entry__c>();
    Set<Id> offeringIds = new Set<Id>();
    for (Waitlist_Entry__c entry : [
      SELECT Id, Course_Offering__c
      FROM Waitlist_Entry__c
      WHERE Status__c = 'Offered' AND Offer_Expires__c < :System.now()
      WITH SYSTEM_MODE
      LIMIT 2000
    ]) {
      expired.add(
        new Waitlist_Entry__c(
          Id = entry.Id,
          Status__c = 'Expired',
          Responded_On__c = System.now()
        )
      );
      offeringIds.add(entry.Course_Offering__c);
    }
    if (expired.isEmpty()) {
      return 0;
    }
    new Writer().updateRecords(expired);
    SeatService.recalculate(offeringIds);
    offerNext(offeringIds);
    return expired.size();
  }

  // ------------------------------------------------------------------- reads

  public static Waitlist getWaitlist(Id offeringId) {
    CourseOffering cls = [
      SELECT Id, Name, EnrollmentCapacity, Class_Status__c
      FROM CourseOffering
      WHERE Id = :offeringId
      WITH USER_MODE
    ];
    Waitlist view = new Waitlist();
    view.className = cls.Name;
    view.capacity = cls.EnrollmentCapacity == null
      ? null
      : cls.EnrollmentCapacity;
    view.taken = SeatService.countTaken(new Set<Id>{ offeringId })
      .get(offeringId);
    view.reserved = SeatService.countReserved(new Set<Id>{ offeringId }, null)
      .get(offeringId);
    view.available = view.capacity == null
      ? null
      : Math.max(0, view.capacity - view.taken - view.reserved);
    view.classStatus = cls.Class_Status__c;
    view.canManage = canManage();
    Integer position = 0;
    for (Waitlist_Entry__c entry : entries('Course_Offering__c', offeringId)) {
      Entry item = toEntry(entry);
      if (entry.Status__c == 'Waiting') {
        item.position = ++position;
      }
      view.entries.add(item);
    }
    return view;
  }

  /** A learner's waitlist entries (Learner 360 and portal). */
  public static List<Entry> learnerEntries(Id learnerAccountId) {
    List<Entry> result = new List<Entry>();
    for (Waitlist_Entry__c entry : entries('Learner__c', learnerAccountId)) {
      Entry item = toEntry(entry);
      if (entry.Status__c == 'Waiting') {
        item.position = positionOf(entry);
      }
      result.add(item);
    }
    return result;
  }

  // ----------------------------------------------------------------- helpers

  private static void close(
    Id entryId,
    String status,
    Set<String> allowed,
    String reason
  ) {
    assertCanManage();
    Waitlist_Entry__c entry = load(entryId, true);
    if (!allowed.contains(entry.Status__c)) {
      throw new AppException(
        'This waitlist entry is ' + entry.Status__c.toLowerCase() + '.'
      );
    }
    Waitlist_Entry__c change = new Waitlist_Entry__c(
      Id = entry.Id,
      Status__c = status,
      Responded_On__c = System.now()
    );
    if (String.isNotBlank(reason)) {
      change.Notes__c =
        (String.isBlank(entry.Notes__c) ? '' : entry.Notes__c + '\n') +
        status +
        ': ' +
        reason.left(200);
    }
    new Writer().updateRecords(new List<SObject>{ change });
    SeatService.recalculate(new Set<Id>{ entry.Course_Offering__c });
    offerNext(new Set<Id>{ entry.Course_Offering__c });
  }

  private static List<Waitlist_Entry__c> entries(String field, Id value) {
    return Database.queryWithBinds(
      'SELECT Id, Name, Learner__c, Learner__r.Name, Status__c, Priority__c, ' +
        'Requested_On__c, Offer_Expires__c, Notes__c, Enrolment__c, ' +
        'Course_Offering__c, Course_Offering__r.Name ' +
        'FROM Waitlist_Entry__c WHERE ' +
        field +
        ' = :value ' +
        'ORDER BY Priority__c DESC NULLS LAST, Requested_On__c ASC, Name ASC LIMIT 500',
      new Map<String, Object>{ 'value' => value },
      AccessLevel.USER_MODE
    );
  }

  private static Integer positionOf(Waitlist_Entry__c entry) {
    Integer position = 0;
    for (Waitlist_Entry__c other : [
      SELECT Id
      FROM Waitlist_Entry__c
      WHERE
        Course_Offering__c = :entry.Course_Offering__c
        AND Status__c = 'Waiting'
      WITH SYSTEM_MODE
      ORDER BY Priority__c DESC NULLS LAST, Requested_On__c ASC, Name ASC
    ]) {
      position++;
      if (other.Id == entry.Id) {
        return position;
      }
    }
    return null;
  }

  private static Entry toEntry(Waitlist_Entry__c entry) {
    Entry item = new Entry();
    item.id = entry.Id;
    item.name = entry.Name;
    item.learnerAccountId = entry.Learner__c;
    item.learnerName = entry.Learner__r?.Name;
    item.status = entry.Status__c;
    item.priority = entry.Priority__c == null
      ? 0
      : entry.Priority__c.intValue();
    item.requestedOn = entry.Requested_On__c;
    item.offerExpires = entry.Offer_Expires__c;
    item.notes = entry.Notes__c;
    item.enrolmentId = entry.Enrolment__c;
    item.className = entry.Course_Offering__r?.Name;
    item.offeringId = entry.Course_Offering__c;
    return item;
  }

  private static Waitlist_Entry__c load(Id entryId, Boolean lock) {
    List<Waitlist_Entry__c> rows = lock
      ? [
          SELECT
            Id,
            Status__c,
            Course_Offering__c,
            Learner__c,
            Application__c,
            Discount_Code__c,
            Offer_Expires__c,
            Notes__c
          FROM Waitlist_Entry__c
          WHERE Id = :entryId
          WITH SYSTEM_MODE
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Status__c,
            Course_Offering__c,
            Learner__c,
            Application__c,
            Discount_Code__c,
            Offer_Expires__c,
            Notes__c
          FROM Waitlist_Entry__c
          WHERE Id = :entryId
          WITH SYSTEM_MODE
        ];
    if (rows.isEmpty()) {
      throw new AppException('Waitlist entry not found.');
    }
    // The class must be visible to the user acting on its waitlist.
    if (
      [
        SELECT COUNT()
        FROM CourseOffering
        WHERE Id = :rows[0].Course_Offering__c
        WITH USER_MODE
      ] == 0
    ) {
      throw new AppException('Waitlist entry not found or not accessible.');
    }
    return rows[0];
  }

  private static Integer freeSeats(CourseOffering cls) {
    if (cls.EnrollmentCapacity == null) {
      return 9999;
    }
    return cls.EnrollmentCapacity -
      SeatService.countTaken(new Set<Id>{ cls.Id }).get(cls.Id) -
      SeatService.countReserved(new Set<Id>{ cls.Id }, null).get(cls.Id);
  }

  private static Integer waitingCount(Id offeringId) {
    return [
      SELECT COUNT()
      FROM Waitlist_Entry__c
      WHERE Course_Offering__c = :offeringId AND Status__c = 'Waiting'
      WITH SYSTEM_MODE
    ];
  }

  public static Boolean canManage() {
    return Schema.SObjectType.Waitlist_Entry__c.isCreateable();
  }

  private static void assertCanManage() {
    if (!canManage()) {
      throw new AppException('You do not have permission to manage waitlists.');
    }
  }

  /** Waitlist writes, authorised by object access checked in assertCanManage. */
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
  }
}
