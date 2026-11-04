@IsTest
private class CollegeProvisionalServiceTest {
  private static Programme_Enrolment__c enrolment(Id enrolmentId) {
    return [
      SELECT
        Id,
        Status__c,
        Status_Reason__c,
        Payment_Due_By__c,
        Expiry_Reminder_Sent__c,
        Confirmation_Sent__c,
        Roll_Number__c
      FROM Programme_Enrolment__c
      WHERE Id = :enrolmentId
    ];
  }

  private static List<Programme_Enrolment__c> scope(Id enrolmentId) {
    return new List<Programme_Enrolment__c>{ enrolment(enrolmentId) };
  }

  private static Integer messages(String eventKey) {
    return [SELECT COUNT() FROM Message__c WHERE Event__c = :eventKey];
  }

  @IsTest
  static void unpaidProvisionalExpiresOnceAndFreesTheSeat() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(1, 3);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      Date later = Date.today().addDays(10);
      Test.startTest();
      System.assertEquals(
        1,
        CollegeProvisionalService.processOverdue(scope(enrolmentId), later)
      );
      System.assertEquals(
        0,
        CollegeProvisionalService.processOverdue(scope(enrolmentId), later),
        'Retry is a no-op'
      );
      Test.stopTest();

      System.assertEquals('Expired', enrolment(enrolmentId).Status__c);
      System.assertEquals(
        'Expired',
        [
          SELECT Status__c
          FROM Seat_Reservation__c
          WHERE Programme_Enrolment__c = :enrolmentId
        ]
        .Status__c
      );
      System.assertEquals(
        0,
        [
          SELECT Reserved_Regular__c
          FROM Campus_Branch__c
          WHERE Id = :fixture.intake.Id
        ]
        .Reserved_Regular__c
      );
      System.assertEquals(
        'Cancelled',
        [
          SELECT Status__c
          FROM Student_Invoice__c
          WHERE Programme_Enrolment__c = :enrolmentId
        ]
        .Status__c
      );
      System.assertEquals(
        'Enrollment Failed',
        [
          SELECT College_Stage__c
          FROM IndividualApplication
          WHERE Id = :fixture.admission.Id
        ]
        .College_Stage__c
      );
      // The freed seat can be given to the next applicant.
      IndividualApplication next = CollegeTestFactory.admission(
        fixture,
        'Next'
      );
      System.assertNotEquals(null, InterviewService.admit(next.Id));
    }
  }

  @IsTest
  static void pendingDemandDraftKeepsTheSeatForTheDean() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 3);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      Student_Invoice__c invoice = CollegeTestFactory.invoiceOf(enrolmentId);
      BillingService.PaymentResult dd = CollegeTestFactory.pay(
        invoice.Id,
        invoice.Total__c,
        'Demand Draft'
      );
      System.assertEquals('Pending', dd.status);
      System.assertEquals(
        null,
        enrolment(enrolmentId).Roll_Number__c,
        'A pending DD never releases a roll number'
      );

      Test.startTest();
      System.assertEquals(
        0,
        CollegeProvisionalService.processOverdue(
          scope(enrolmentId),
          Date.today().addDays(10)
        )
      );
      Test.stopTest();
      System.assertEquals('Provisional', enrolment(enrolmentId).Status__c);

      // Make it overdue today so it appears on the Dean's list.
      update new Programme_Enrolment__c(
        Id = enrolmentId,
        Payment_Due_By__c = Date.today().addDays(-1)
      );
      List<CollegeProvisionalService.OverdueRow> rows = CollegeAdmissionsController.getOverdue();
      System.assertEquals(1, rows.size());
      System.assertEquals(invoice.Total__c, rows[0].awaitingClearance);

      try {
        CollegeProvisionalService.cancel(enrolmentId, 'Changed mind');
        System.assert(false, 'Cancel must wait for the pending DD');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('awaiting clearance'));
      }

      Date newDate = Date.today().addDays(5);
      CollegeAdmissionsController.extendPayment(
        enrolmentId,
        newDate,
        'DD deposited, bank clearing'
      );
      Programme_Enrolment__c extended = enrolment(enrolmentId);
      System.assertEquals(newDate, extended.Payment_Due_By__c);
      System.assert(extended.Status_Reason__c.contains('DD deposited'));
      System.assertEquals(
        newDate,
        [
            SELECT Expires_On__c
            FROM Seat_Reservation__c
            WHERE Programme_Enrolment__c = :enrolmentId
          ]
          .Expires_On__c.date()
      );

      // Clearing the DD releases the roll number and sends one confirmation.
      BillingService.confirmPayment(dd.paymentId);
      Programme_Enrolment__c enrolled = enrolment(enrolmentId);
      System.assertEquals('Enrolled', enrolled.Status__c);
      System.assertNotEquals(null, enrolled.Roll_Number__c);
      System.assert(enrolled.Confirmation_Sent__c);
      Integer confirmations = messages('College_Admission_Confirmed');
      System.assert(confirmations > 0);
      ProgrammeEnrolmentService.onInvoicesPaid(new Set<Id>{ invoice.Id });
      CollegeProvisionalService.confirmAdmissions(new Set<Id>{ enrolmentId });
      System.assertEquals(
        confirmations,
        messages('College_Admission_Confirmed'),
        'Confirmation is not repeated'
      );
      System.assertEquals(
        enrolled.Roll_Number__c,
        enrolment(enrolmentId).Roll_Number__c
      );
    }
  }

  @IsTest
  static void deanCancelsUnpaidAdmission() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(1, 3);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      try {
        CollegeAdmissionsController.extendPayment(enrolmentId, null, 'x');
        System.assert(false, 'Date required');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      try {
        CollegeProvisionalService.cancel(enrolmentId, ' ');
        System.assert(false, 'Reason required');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('reason'));
      }
      Test.startTest();
      CollegeAdmissionsController.cancelAdmission(
        enrolmentId,
        'Student joined another college'
      );
      Test.stopTest();
      Programme_Enrolment__c cancelled = enrolment(enrolmentId);
      System.assertEquals('Cancelled', cancelled.Status__c);
      System.assertEquals(
        'Student joined another college',
        cancelled.Status_Reason__c
      );
      System.assertEquals(
        'Released',
        [
          SELECT Status__c
          FROM Seat_Reservation__c
          WHERE Programme_Enrolment__c = :enrolmentId
        ]
        .Status__c
      );
      System.assert(messages('College_Admission_Cancelled') > 0);
      try {
        CollegeProvisionalService.extend(
          enrolmentId,
          Date.today().addDays(3),
          'Too late'
        );
        System.assert(false, 'Closed enrolments cannot be extended');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('provisional'));
      }
    }
  }

  @IsTest
  static void reminderIsSentOncePerDueDate() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(1, 2);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      Test.startTest();
      System.assertEquals(
        1,
        CollegeProvisionalService.sendReminders(
          scope(enrolmentId),
          Date.today()
        )
      );
      System.assertEquals(
        0,
        CollegeProvisionalService.sendReminders(
          scope(enrolmentId),
          Date.today()
        )
      );
      Test.stopTest();
      System.assert(enrolment(enrolmentId).Expiry_Reminder_Sent__c);
      System.assert(messages('College_Payment_Due_Soon') > 0);
    }
  }

  @IsTest
  static void nightlyJobExpiresAndReconciliationRepairsCounters() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(3, 1);
    System.runAs(fixture.dean) {
      Id enrolmentId = InterviewService.admit(fixture.admission.Id);
      update new Campus_Branch__c(
        Id = fixture.intake.Id,
        Reserved_Regular__c = 2,
        Finalised_Regular__c = 1
      );
      CollegeAdmissionsJob job = new CollegeAdmissionsJob(
        CollegeAdmissionsJob.PROVISIONAL
      );
      job.today = Date.today().addDays(5);
      Test.startTest();
      Database.executeBatch(job, 5);
      Test.stopTest();
      System.assertEquals('Expired', enrolment(enrolmentId).Status__c);
      Integer drifted = CollegeAdmissionsJob.reconcile(
        [
          SELECT
            Id,
            Reserved_Regular__c,
            Reserved_Lateral__c,
            Finalised_Regular__c,
            Finalised_Lateral__c
          FROM Campus_Branch__c
          WHERE Id = :fixture.intake.Id
        ]
      );
      System.assertEquals(1, drifted);
      Campus_Branch__c intake = [
        SELECT Reserved_Regular__c, Finalised_Regular__c
        FROM Campus_Branch__c
        WHERE Id = :fixture.intake.Id
      ];
      System.assertEquals(0, intake.Reserved_Regular__c);
      System.assertEquals(0, intake.Finalised_Regular__c);
      System.assertEquals(
        0,
        CollegeAdmissionsJob.reconcile(
          [
            SELECT
              Id,
              Reserved_Regular__c,
              Reserved_Lateral__c,
              Finalised_Regular__c,
              Finalised_Lateral__c
            FROM Campus_Branch__c
            WHERE Id = :fixture.intake.Id
          ]
        ),
        'Correct counters are left alone'
      );
    }
    System.assert(
      KemJobs.jobFor('KEM College Admissions') instanceof CollegeAdmissionsJob
    );
  }

  @IsTest
  static void collegeDuesSummariseBilledPaidAndClearance() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(2, 3);
    System.runAs(fixture.dean) {
      Id paidId = CollegeTestFactory.enrolPaid(fixture, fixture.admission);
      IndividualApplication second = CollegeTestFactory.admission(
        fixture,
        'Second'
      );
      Id pendingId = InterviewService.admit(second.Id);
      Student_Invoice__c invoice = CollegeTestFactory.invoiceOf(pendingId);
      CollegeTestFactory.pay(invoice.Id, 40000, 'Cheque');
      Test.startTest();
      CollegeDuesService.Dues dues = CollegeAdmissionsController.getDues();
      Test.stopTest();
      System.assertEquals(1, dues.rows.size());
      CollegeDuesService.DuesRow row = dues.rows[0];
      Decimal each = invoice.Total__c;
      System.assertEquals(each * 2, row.billed);
      System.assertEquals(each, row.paid);
      System.assertEquals(each, row.due);
      System.assertEquals(40000, row.awaitingClearance);
      System.assertEquals(row.due, dues.total.due);
      System.assertNotEquals(null, CollegeAdmissionsController.getOverdue());
      System.assertNotEquals(null, paidId);
    }
  }

  @IsTest
  static void onlyTheDeanExtendsOrCancels() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(1, 3);
    Id enrolmentId;
    System.runAs(fixture.dean) {
      enrolmentId = InterviewService.admit(fixture.admission.Id);
    }
    User finance = TestDataFactory.createUser(
      new List<String>{ 'KEM_Finance' }
    );
    System.runAs(finance) {
      System.assertEquals(
        null,
        CollegeAdmissionsController.getOverdue(),
        'Hidden for non-Deans'
      );
      try {
        CollegeProvisionalService.extend(
          enrolmentId,
          Date.today().addDays(4),
          'Please'
        );
        System.assert(false, 'Dean permission required');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('permission'));
      }
      try {
        CollegeAdmissionsController.cancelAdmission(enrolmentId, 'No');
        System.assert(false, 'Dean permission required');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
    }
  }
}
