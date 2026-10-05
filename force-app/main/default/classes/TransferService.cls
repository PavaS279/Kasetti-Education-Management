/**
 * Moves a learner's enrolment to another class in one step.
 *
 * The learner is enrolled in the target class (seat control, current price
 * list, the same discount code), the original enrolment ends as Withdrew with
 * a link both ways, and its seat is released (and offered to that class's
 * waitlist). Attendance and results stay on the original enrolment as history.
 *
 * Money: if the original enrolment was never invoiced, its uninvoiced fee lines
 * are dropped and the new enrolment is billed normally. If it was invoiced, the
 * new enrolment is billed only for a price increase (one adjustment line); a
 * price decrease is recorded as Credit_Due__c and issued as a credit note
 * (CreditService) to be used on a later invoice or refunded.
 */
public with sharing class TransferService {
  public class TransferRequest {
    @AuraEnabled
    public Id enrolmentId { get; set; }
    @AuraEnabled
    public Id targetOfferingId { get; set; }
    @AuraEnabled
    public Date effectiveDate { get; set; }
    @AuraEnabled
    public String reason { get; set; }
  }

  public class TransferPreview {
    @AuraEnabled
    public String fromClass;
    @AuraEnabled
    public String toClass;
    @AuraEnabled
    public Decimal currentTotal;
    @AuraEnabled
    public Decimal newTotal;
    @AuraEnabled
    public Decimal difference;
    @AuraEnabled
    public Boolean alreadyInvoiced;
    @AuraEnabled
    public String billingOutcome;
    @AuraEnabled
    public Integer seatsRemaining;
    @AuraEnabled
    public List<String> blockers = new List<String>();
  }

  public static TransferPreview preview(TransferRequest request) {
    CourseOfferingParticipant source = loadSource(request);
    EnrolmentService.Preview target = EnrolmentService.preview(
      enrolmentRequest(source, request.targetOfferingId)
    );
    TransferPreview result = new TransferPreview();
    result.fromClass = source.CourseOffering.Name;
    result.toClass = target.offering.Name;
    result.currentTotal = nvl(source.Agreed_Total__c);
    result.newTotal = target.quote.grandTotal;
    result.difference = result.newTotal - result.currentTotal;
    result.alreadyInvoiced = source.Billing_Status__c != 'Not Invoiced';
    result.billingOutcome = outcome(result.alreadyInvoiced, result.difference);
    result.seatsRemaining = target.seatsRemaining;
    result.blockers.addAll(target.blockers);
    result.blockers.addAll(sourceProblems(source, request));
    return result;
  }

  public static Id transfer(TransferRequest request) {
    if (request == null || String.isBlank(request.reason)) {
      throw new AppException('Enter a reason for the transfer.');
    }
    CourseOfferingParticipant source = loadSource(request);
    List<String> problems = sourceProblems(source, request);
    if (!problems.isEmpty()) {
      throw new AppException(problems[0]);
    }
    RecordAccess.assertEditable(source.Id);
    Date effective = request.effectiveDate == null
      ? Date.today()
      : request.effectiveDate;

    Savepoint sp = Database.setSavepoint();
    try {
      EnrolmentService.EnrolmentResult enrolled = EnrolmentService.enrol(
        enrolmentRequest(source, request.targetOfferingId)
      );
      Id targetId = enrolled.enrolmentId;
      String targetName = [
        SELECT Name
        FROM CourseOffering
        WHERE Id = :request.targetOfferingId
        WITH SYSTEM_MODE
      ]
      .Name;
      Decimal difference =
        enrolled.quote.grandTotal - nvl(source.Agreed_Total__c);
      Boolean invoiced = source.Billing_Status__c != 'Not Invoiced';
      Writer writer = new Writer();

      CourseOfferingParticipant target = new CourseOfferingParticipant(
        Id = targetId,
        Transferred_From__c = source.Id,
        Transfer_Adjustment__c = difference,
        Application__c = source.Application__c,
        StartDate = effective
      );
      if (invoiced) {
        // The original invoice already covers the course; bill only the increase.
        writer.deleteRecords(feeLines(targetId, false));
        if (difference > 0) {
          writer.insertRecords(
            new List<SObject>{
              new Enrolment_Fee_Line__c(
                Enrolment__c = targetId,
                Fee_Type__c = 'Other',
                Billing_Frequency__c = 'One-time',
                Description__c = ('Transfer price difference from ' +
                  source.CourseOffering.Name)
                  .left(255),
                Unit_Amount__c = difference,
                Discount_Amount__c = 0,
                Tax_Rate__c = 0,
                Tax_Amount__c = 0,
                Line_Total__c = difference
              )
            }
          );
          target.Billing_Status__c = 'Not Invoiced';
        } else {
          target.Billing_Status__c = source.Billing_Status__c;
          if (difference < 0) {
            target.Credit_Due__c = -difference;
          }
        }
      } else {
        // Never invoiced: the old price simply lapses.
        writer.deleteRecords(feeLines(source.Id, true));
      }
      if (invoiced && difference < 0) {
        // Money already paid for the dearer class is held as a credit note,
        // used on the next invoice or refunded.
        CreditService.issueForTransfer(
          targetId,
          source.Id,
          -difference,
          ('Transfer from ' +
            source.CourseOffering.Name +
            ' to ' +
            targetName +
            ': ' +
            request.reason)
            .left(255)
        );
      }
      writer.updateRecords(
        new List<SObject>{
          target,
          new CourseOfferingParticipant(
            Id = source.Id,
            ParticipationStatus = 'Withdrew',
            DroppedDateTime = System.now(),
            EndDate = effective,
            Transferred_To__c = targetId,
            Withdrawal_Reason__c = ('Transferred to ' +
              targetName +
              ': ' +
              request.reason)
              .left(255)
          )
        }
      );
      return targetId;
    } catch (Exception e) {
      Database.rollback(sp);
      if (!(e instanceof AppException)) {
        Logger.error('TransferService.transfer', e, request.enrolmentId);
      }
      throw e;
    }
  }

  // ----------------------------------------------------------------- helpers

  private static List<String> sourceProblems(
    CourseOfferingParticipant source,
    TransferRequest request
  ) {
    List<String> problems = new List<String>();
    if (!SeatService.SEAT_STATUSES.contains(source.ParticipationStatus)) {
      problems.add('Only active enrolments can be transferred.');
    }
    if (source.CourseOfferingId == request.targetOfferingId) {
      problems.add('Choose a different class.');
    }
    if (source.Discount_Approval_Status__c == 'Pending') {
      problems.add(
        'Decide the pending discount before transferring this enrolment.'
      );
    }
    if (
      request.effectiveDate != null &&
      source.StartDate != null &&
      request.effectiveDate < source.StartDate
    ) {
      problems.add('The transfer date cannot be before the enrolment started.');
    }
    return problems;
  }

  private static String outcome(Boolean invoiced, Decimal difference) {
    if (!invoiced) {
      return 'Not invoiced yet: the new class is billed at its own price.';
    }
    if (difference > 0) {
      return 'Already invoiced: only the difference is billed on the new enrolment.';
    }
    if (difference < 0) {
      return 'Already invoiced: the difference is issued to the family as a credit note.';
    }
    return 'Already invoiced: same price, nothing more to bill.';
  }

  private static EnrolmentService.EnrolmentRequest enrolmentRequest(
    CourseOfferingParticipant source,
    Id targetOfferingId
  ) {
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = source.ParticipantAccountId;
    request.offeringId = targetOfferingId;
    request.discountCode = source.Discount__r?.Code__c;
    return request;
  }

  private static CourseOfferingParticipant loadSource(TransferRequest request) {
    if (
      request == null ||
      request.enrolmentId == null ||
      request.targetOfferingId == null
    ) {
      throw new AppException('Choose the enrolment and the new class.');
    }
    List<CourseOfferingParticipant> rows = [
      SELECT
        Id,
        ParticipantAccountId,
        CourseOfferingId,
        CourseOffering.Name,
        ParticipationStatus,
        StartDate,
        Agreed_Total__c,
        Billing_Status__c,
        Discount_Approval_Status__c,
        Discount__r.Code__c,
        Application__c
      FROM CourseOfferingParticipant
      WHERE Id = :request.enrolmentId
      WITH USER_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Enrolment not found or not accessible.');
    }
    return rows[0];
  }

  private static List<Enrolment_Fee_Line__c> feeLines(
    Id enrolmentId,
    Boolean uninvoicedOnly
  ) {
    List<Enrolment_Fee_Line__c> lines = new List<Enrolment_Fee_Line__c>();
    for (Enrolment_Fee_Line__c line : [
      SELECT Id, Invoiced__c
      FROM Enrolment_Fee_Line__c
      WHERE Enrolment__c = :enrolmentId
      WITH SYSTEM_MODE
    ]) {
      if (!uninvoicedOnly || !line.Invoiced__c) {
        lines.add(line);
      }
    }
    return lines;
  }

  private static Decimal nvl(Decimal value) {
    return value == null ? 0 : value;
  }

  /** Writes authorised by edit access to the original enrolment (checked first). */
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

    void deleteRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.delete(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
