/** Atomic and idempotent college admission-to-provisional-enrolment orchestration. */
public without sharing class ProgrammeEnrolmentService {
  /** Releases eligible provisional enrolments after confirmed allocations refresh invoices. */
  public static void onInvoicesPaid(Set<Id> invoiceIds) {
    if (invoiceIds == null || invoiceIds.isEmpty())
      return;
    Set<Id> eligible = new Set<Id>();
    for (Student_Invoice__c invoice : [
      SELECT
        Id,
        Programme_Enrolment__c,
        Year_Of_Study__c,
        Invoice_Kind__c,
        Status__c,
        Amount_Paid__c,
        Balance_Due__c,
        Programme_Enrolment__r.Status__c,
        Programme_Enrolment__r.Entry_Year_Of_Study__c,
        Programme_Enrolment__r.Programme__r.Roll_Release_Rule__c,
        Programme_Enrolment__r.Programme__r.Roll_Release_Amount__c
      FROM Student_Invoice__c
      WHERE Id IN :invoiceIds AND Programme_Enrolment__c != NULL
      WITH SYSTEM_MODE
    ]) {
      Programme_Enrolment__c enrolment = invoice.Programme_Enrolment__r;
      if (
        enrolment.Status__c != 'Provisional' ||
        invoice.Year_Of_Study__c != enrolment.Entry_Year_Of_Study__c
      )
        continue;
      String rule = enrolment.Programme__r.Roll_Release_Rule__c;
      Boolean release = rule == 'Admission Fee'
        ? invoice.Invoice_Kind__c == 'Admission' && invoice.Balance_Due__c <= 0
        : rule == 'Minimum Amount'
            ? invoice.Invoice_Kind__c == 'Annual' &&
              invoice.Amount_Paid__c >=
              enrolment.Programme__r.Roll_Release_Amount__c
            : invoice.Invoice_Kind__c == 'Annual' &&
              invoice.Balance_Due__c <= 0;
      if (release)
        eligible.add(enrolment.Id);
    }
    for (Id enrolmentId : eligible)
      releaseRoll(enrolmentId);
    if (!eligible.isEmpty())
      CollegeProvisionalService.confirmAdmissions(eligible);
  }

  private static void releaseRoll(Id enrolmentId) {
    Programme_Enrolment__c enrolment = [
      SELECT Id, Status__c
      FROM Programme_Enrolment__c
      WHERE Id = :enrolmentId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (enrolment.Status__c == 'Enrolled')
      return;
    if (enrolment.Status__c != 'Provisional')
      return;
    Seat_Reservation__c reservation = [
      SELECT Id
      FROM Seat_Reservation__c
      WHERE Programme_Enrolment__c = :enrolmentId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    CollegeSeatService.finalise(reservation.Id);
    RollNumberService.issue(enrolmentId);
    Database.update(
      new Programme_Enrolment__c(Id = enrolmentId, Status__c = 'Enrolled'),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static Id admit(Id applicationId) {
    RecordAccess.assertPermission(InterviewService.PERMISSION);
    RecordAccess.assertEditable(applicationId);
    Savepoint checkpoint = Database.setSavepoint();
    try {
      return admitAtomic(applicationId);
    } catch (Exception failure) {
      Database.rollback(checkpoint);
      throw failure;
    }
  }

  private static Id admitAtomic(Id applicationId) {
    IndividualApplication admission = [
      SELECT
        Id,
        AccountId,
        College_Mode__c,
        College_Stage__c,
        Interview_Outcome__c,
        Branch__c,
        Learning_Course__c,
        Learning_Program__c,
        Learning_Program__r.Payment_Window_Days__c,
        Learning_Program__r.Roll_Release_Rule__c,
        Campus_Branch__c,
        Academic_Year__c,
        Entry_Route__c,
        Entry_Year_Of_Study__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    List<Programme_Enrolment__c> existing = [
      SELECT Id
      FROM Programme_Enrolment__c
      WHERE Application__c = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (!existing.isEmpty())
      return existing[0].Id;
    validate(admission);

    Integer paymentWindowDays = admission.Learning_Program__r.Payment_Window_Days__c ==
      null
      ? 7
      : admission.Learning_Program__r.Payment_Window_Days__c.intValue();
    Date paymentDueBy = Date.today().addDays(paymentWindowDays);
    Datetime expiresOn = Datetime.newInstance(
      paymentDueBy,
      Time.newInstance(23, 59, 59, 999)
    );
    Id reservationId = CollegeSeatService.reserve(applicationId, expiresOn);

    Programme_Enrolment__c enrolment = new Programme_Enrolment__c(
      Student__c = admission.AccountId,
      Programme__c = admission.Learning_Program__c,
      Branch__c = admission.Learning_Course__c,
      Campus__c = admission.Branch__c,
      Campus_Branch__c = admission.Campus_Branch__c,
      Application__c = admission.Id,
      Entry_Route__c = admission.Entry_Route__c,
      Entry_Year_Of_Study__c = admission.Entry_Year_Of_Study__c,
      Admission_Year__c = Integer.valueOf(admission.Academic_Year__c.left(4)),
      Academic_Year__c = admission.Academic_Year__c,
      Current_Year_Of_Study__c = admission.Entry_Year_Of_Study__c,
      Status__c = 'Provisional',
      Payment_Due_By__c = paymentDueBy
    );
    Database.insert(enrolment, AccessLevel.SYSTEM_MODE);
    Database.update(
      new Seat_Reservation__c(
        Id = reservationId,
        Programme_Enrolment__c = enrolment.Id
      ),
      AccessLevel.SYSTEM_MODE
    );
    String invoiceKind = admission.Learning_Program__r.Roll_Release_Rule__c ==
      'Admission Fee'
      ? 'Admission'
      : 'Annual';
    BillingService.createProgrammeInvoiceSystem(
      enrolment.Id,
      enrolment.Entry_Year_Of_Study__c.intValue(),
      invoiceKind
    );
    return enrolment.Id;
  }

  private static void validate(IndividualApplication admission) {
    if (
      !admission.College_Mode__c ||
      admission.College_Stage__c != 'Ready For Decision' ||
      admission.Interview_Outcome__c != 'Pass'
    ) {
      throw new AppException(
        'Only a passed college admission at Ready For Decision can be admitted.'
      );
    }
    if (
      admission.AccountId == null ||
      admission.Branch__c == null ||
      admission.Learning_Course__c == null ||
      admission.Learning_Program__c == null ||
      admission.Campus_Branch__c == null ||
      String.isBlank(admission.Academic_Year__c) ||
      String.isBlank(admission.Entry_Route__c) ||
      admission.Entry_Year_Of_Study__c == null
    ) {
      throw new AppException(
        'Complete the college admission programme, campus, route and academic year before admitting.'
      );
    }
  }
}
