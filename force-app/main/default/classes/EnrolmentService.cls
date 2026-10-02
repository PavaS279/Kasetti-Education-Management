/**
 * Enrols learners into classes (CourseOfferingParticipant) with seat control
 * and an immutable snapshot of the agreed price (Enrolment_Fee_Line__c).
 *
 * The user's create access is proven by a user-mode insert of the enrolment;
 * system-managed fields (agreed amounts, discount, approval, links) and the
 * fee-line snapshot are then written in system mode.
 */
public with sharing class EnrolmentService {
  public static final String APPROVE_PERMISSION = 'KEM_Approve_Discounts';
  private static final Set<String> ENROLLABLE_CLASS_STATUSES = new Set<String>{
    'Open',
    'In Progress'
  };

  public class EnrolmentRequest {
    @AuraEnabled
    public Id learnerAccountId { get; set; }
    @AuraEnabled
    public Id offeringId { get; set; }
    @AuraEnabled
    public Id applicationId { get; set; }
    @AuraEnabled
    public String discountCode { get; set; }
  }

  public class EnrolmentResult {
    @AuraEnabled
    public Id enrolmentId;
    @AuraEnabled
    public PricingService.Quote quote;
    @AuraEnabled
    public Integer seatsRemaining;
    @AuraEnabled
    public Boolean approvalRequired;
  }

  public class Preview {
    @AuraEnabled
    public CourseOffering offering;
    @AuraEnabled
    public PricingService.Quote quote;
    @AuraEnabled
    public Integer seatsRemaining;
    @AuraEnabled
    public List<String> blockers = new List<String>();
  }

  public static Preview preview(EnrolmentRequest request) {
    Preview result = new Preview();
    result.offering = loadOffering(request.offeringId, false);
    result.quote = quoteFor(result.offering, request.discountCode);
    result.seatsRemaining = seatsRemaining(
      result.offering,
      SeatService.countTaken(new Set<Id>{ result.offering.Id })
        .get(result.offering.Id)
    );
    result.blockers.addAll(
      blockers(result.offering, result.seatsRemaining, request)
    );
    if (result.quote.lines.isEmpty()) {
      result.blockers.add(
        'No price is set for this course. Add a price before enrolling.'
      );
    }
    return result;
  }

  public static EnrolmentResult enrol(EnrolmentRequest request) {
    if (
      request == null ||
      request.learnerAccountId == null ||
      request.offeringId == null
    ) {
      throw new AppException('Choose a learner and a class.');
    }
    Savepoint sp = Database.setSavepoint();
    try {
      // Lock the class row so concurrent enrolments cannot oversell the last seat.
      CourseOffering offering = loadOffering(request.offeringId, true);
      Integer remaining = seatsRemaining(
        offering,
        SeatService.countTaken(new Set<Id>{ offering.Id }).get(offering.Id)
      );
      List<String> problems = blockers(offering, remaining, request);
      if (!problems.isEmpty()) {
        throw new AppException(problems[0]);
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
        throw new AppException(
          'Only learners can be enrolled. Set the person\'s role to Learner first.'
        );
      }
      PricingService.Quote quote = quoteFor(offering, request.discountCode);
      if (quote.lines.isEmpty()) {
        throw new AppException(
          'No price is set for this course. Add a price before enrolling.'
        );
      }
      if (String.isNotBlank(request.discountCode) && quote.discountId == null) {
        throw new AppException(String.join(quote.warnings, ' '));
      }

      CourseOfferingParticipant enrolment = new CourseOfferingParticipant(
        CourseOfferingId = offering.Id,
        ParticipantContactId = learner.PersonContactId,
        ParticipantAccountId = learner.Id,
        ParticipantAffiliation = 'Student',
        ParticipationStatus = 'Enrolled',
        RegistrationDateTime = System.now(),
        StartDate = offering.StartDate == null
          ? Date.today()
          : offering.StartDate.date(),
        EndDate = offering.EndDate == null ? null : offering.EndDate.date()
      );
      Database.insert(enrolment, AccessLevel.USER_MODE);

      Database.update(
        new CourseOfferingParticipant(
          Id = enrolment.Id,
          Application__c = request.applicationId,
          Branch__c = offering.Branch__c,
          Discount__c = quote.discountId,
          Discount_Approval_Status__c = quote.approvalRequired
            ? 'Pending'
            : 'Not Required',
          Agreed_Subtotal__c = quote.subtotal,
          Agreed_Discount__c = quote.discountTotal,
          Agreed_Tax__c = quote.taxTotal,
          Agreed_Total__c = quote.grandTotal,
          Billing_Status__c = 'Not Invoiced'
        ),
        AccessLevel.SYSTEM_MODE
      );
      insertFeeLines(enrolment.Id, quote);
      PricingService.recordUsage(quote.discountId);
      if (request.applicationId != null) {
        ApplicationService.markEnrolled(request.applicationId);
      }

      EnrolmentResult result = new EnrolmentResult();
      result.enrolmentId = enrolment.Id;
      result.quote = quote;
      result.seatsRemaining = remaining - 1;
      result.approvalRequired = quote.approvalRequired;
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      if (!(e instanceof AppException)) {
        Logger.error('EnrolmentService.enrol', e, request.offeringId);
      }
      throw e;
    }
  }

  public static void withdraw(
    Id enrolmentId,
    String reason,
    Date effectiveDate
  ) {
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for the withdrawal.');
    }
    CourseOfferingParticipant enrolment = loadEnrolment(enrolmentId);
    if (!SeatService.SEAT_STATUSES.contains(enrolment.ParticipationStatus)) {
      throw new AppException('Only active enrolments can be withdrawn.');
    }
    Date effective = effectiveDate == null ? Date.today() : effectiveDate;
    if (enrolment.StartDate != null && effective < enrolment.StartDate) {
      effective = enrolment.StartDate;
    }
    RecordAccess.assertEditable(enrolmentId);
    Database.update(
      new CourseOfferingParticipant(
        Id = enrolmentId,
        ParticipationStatus = 'Withdrew',
        DroppedDateTime = System.now(),
        EndDate = effective,
        Withdrawal_Reason__c = reason.left(255)
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Approves or rejects a pending discount. A rejection re-prices the enrolment without it. */
  public static void decideDiscount(Id enrolmentId, Boolean approve) {
    RecordAccess.assertPermission(APPROVE_PERMISSION);
    CourseOfferingParticipant enrolment = loadEnrolment(enrolmentId);
    if (enrolment.Discount_Approval_Status__c != 'Pending') {
      throw new AppException(
        'This enrolment has no discount waiting for approval.'
      );
    }
    if (approve) {
      new Elevated()
        .updateRecord(
          new CourseOfferingParticipant(
            Id = enrolmentId,
            Discount_Approval_Status__c = 'Approved'
          )
        );
      return;
    }
    if (enrolment.Billing_Status__c != 'Not Invoiced') {
      throw new AppException(
        'The enrolment is already invoiced; reverse the invoice before changing its price.'
      );
    }
    CourseOffering offering = loadOffering(enrolment.CourseOfferingId, false);
    PricingService.Quote quote = quoteFor(offering, null);
    new Elevated().deleteFeeLines(enrolmentId);
    insertFeeLines(enrolmentId, quote);
    new Elevated()
      .updateRecord(
        new CourseOfferingParticipant(
          Id = enrolmentId,
          Discount_Approval_Status__c = 'Rejected',
          Agreed_Subtotal__c = quote.subtotal,
          Agreed_Discount__c = quote.discountTotal,
          Agreed_Tax__c = quote.taxTotal,
          Agreed_Total__c = quote.grandTotal
        )
      );
  }

  /**
   * Writes that are authorised by the KEM_Approve_Discounts custom permission
   * (checked by the caller) rather than by record ownership: finance approves
   * discounts on enrolments created by any counsellor.
   */
  private without sharing class Elevated {
    void updateRecord(SObject record) {
      Database.update(record, AccessLevel.SYSTEM_MODE);
    }

    void deleteFeeLines(Id enrolmentId) {
      Database.delete(
        [
          SELECT Id
          FROM Enrolment_Fee_Line__c
          WHERE Enrolment__c = :enrolmentId
          WITH SYSTEM_MODE
        ],
        AccessLevel.SYSTEM_MODE
      );
    }
  }

  // --------------------------------------------------------------- helpers

  private static List<String> blockers(
    CourseOffering offering,
    Integer remaining,
    EnrolmentRequest request
  ) {
    List<String> problems = new List<String>();
    if (!ENROLLABLE_CLASS_STATUSES.contains(offering.Class_Status__c)) {
      problems.add(
        'The class is ' +
          (offering.Class_Status__c == null
            ? 'not open'
            : offering.Class_Status__c.toLowerCase()) +
          ' and is not taking enrolments.'
      );
    } else if (remaining <= 0) {
      problems.add('The class is full.');
    }
    if (request.learnerAccountId != null) {
      Integer active = [
        SELECT COUNT()
        FROM CourseOfferingParticipant
        WHERE
          CourseOfferingId = :offering.Id
          AND ParticipantAccountId = :request.learnerAccountId
          AND ParticipationStatus IN :SeatService.SEAT_STATUSES
        WITH SYSTEM_MODE
      ];
      if (active > 0) {
        problems.add('The learner is already enrolled in this class.');
      }
    }
    if (request.applicationId != null) {
      List<IndividualApplication> applications = [
        SELECT Id, AccountId, Offer_Status__c, Status
        FROM IndividualApplication
        WHERE Id = :request.applicationId
        WITH USER_MODE
      ];
      if (
        applications.isEmpty() ||
        applications[0].AccountId != request.learnerAccountId
      ) {
        problems.add('The application does not belong to this learner.');
      } else if (applications[0].Offer_Status__c != 'Accepted') {
        problems.add('The applicant must accept the offer before enrolment.');
      }
    }
    return problems;
  }

  private static Integer seatsRemaining(
    CourseOffering offering,
    Integer taken
  ) {
    return offering.EnrollmentCapacity == null
      ? 9999
      : offering.EnrollmentCapacity - (taken == null ? 0 : taken);
  }

  private static PricingService.Quote quoteFor(
    CourseOffering offering,
    String discountCode
  ) {
    if (offering.LearningCourseId == null) {
      throw new AppException(
        'The class is not linked to a course, so it cannot be priced.'
      );
    }
    PricingService.QuoteRequest request = new PricingService.QuoteRequest();
    request.courseId = offering.LearningCourseId;
    request.branchId = offering.Branch__c;
    request.deliveryMode = offering.Delivery_Mode__c;
    request.onDate = Date.today();
    request.discountCode = discountCode;
    return PricingService.quote(request);
  }

  private static void insertFeeLines(
    Id enrolmentId,
    PricingService.Quote quote
  ) {
    List<Enrolment_Fee_Line__c> lines = new List<Enrolment_Fee_Line__c>();
    for (PricingService.QuoteLine line : quote.lines) {
      lines.add(
        new Enrolment_Fee_Line__c(
          Enrolment__c = enrolmentId,
          Fee_Price__c = line.feePriceId,
          Fee_Type__c = line.feeType,
          Billing_Frequency__c = line.frequency,
          Description__c = line.description == null
            ? null
            : line.description.left(255),
          Unit_Amount__c = line.unitAmount,
          Discount_Amount__c = line.discountAmount,
          Tax_Rate__c = line.taxRate * 100,
          Tax_Amount__c = line.taxAmount,
          Line_Total__c = line.total
        )
      );
    }
    Database.insert(lines, AccessLevel.SYSTEM_MODE);
  }

  public static CourseOffering loadOffering(Id offeringId, Boolean lock) {
    List<CourseOffering> offerings = lock
      ? [
          SELECT
            Id,
            Name,
            LearningCourseId,
            LearningCourse.Name,
            Branch__c,
            Branch__r.Name,
            Delivery_Mode__c,
            Class_Status__c,
            EnrollmentCapacity,
            Seats_Taken__c,
            StartDate,
            EndDate
          FROM CourseOffering
          WHERE Id = :offeringId
          WITH USER_MODE
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Name,
            LearningCourseId,
            LearningCourse.Name,
            Branch__c,
            Branch__r.Name,
            Delivery_Mode__c,
            Class_Status__c,
            EnrollmentCapacity,
            Seats_Taken__c,
            StartDate,
            EndDate
          FROM CourseOffering
          WHERE Id = :offeringId
          WITH USER_MODE
        ];
    if (offerings.isEmpty()) {
      throw new AppException('Class not found or not accessible.');
    }
    return offerings[0];
  }

  private static CourseOfferingParticipant loadEnrolment(Id enrolmentId) {
    List<CourseOfferingParticipant> rows = [
      SELECT
        Id,
        CourseOfferingId,
        ParticipationStatus,
        StartDate,
        Discount_Approval_Status__c,
        Billing_Status__c
      FROM CourseOfferingParticipant
      WHERE Id = :enrolmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Enrolment not found or not accessible.');
    }
    return rows[0];
  }
}
