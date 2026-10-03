/**
 * Phase 1 completion condition: one learner completes the full journey with
 * financial reconciliation — enquiry, conversion, application, offer,
 * enrolment, timetable, attendance, assessment, invoice, payment and
 * reconciliation — and the family sees the outcome in the portal, with the
 * offer letter, invoice and receipt filed as PDFs.
 */
@IsTest
private class FullJourneyTest {
  @IsTest
  static void learnerCompletesTheJourneyWithReconciledPayment() {
    ChecklistItemGateway.simulateStatusUpdates = true;
    TestDataFactory.createReferenceData();
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );

    System.runAs(TestDataFactory.admin()) {
      // ---------------------------------------------------- set-up
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse(
        'Physics Foundation'
      );
      insert new List<Fee_Price__c>{
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Admission',
          Billing_Frequency__c = 'One-time',
          Amount__c = 1000,
          Effective_From__c = Date.today().addDays(-30)
        ),
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Term',
          Amount__c = 9000,
          Effective_From__c = Date.today().addDays(-30)
        )
      };
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        12
      );
      update new CourseOffering(Id = offering.Id, Teacher_User__c = teacher.Id);
      Date firstMonday = Date.today().addDays(1);
      while (
        !SessionService.runsOn(
          new CourseOfferingSchedule(IsMonday = true),
          firstMonday
        )
      ) {
        firstMonday = firstMonday.addDays(1);
      }
      insert new CourseOfferingSchedule(
        CourseOfferingId = offering.Id,
        Description = 'Mondays 16:00',
        IsMonday = true,
        StartTime = Time.newInstance(16, 0, 0, 0),
        EndTime = Time.newInstance(17, 30, 0, 0),
        StartDate = firstMonday
      );
      update new CourseOffering(
        Id = offering.Id,
        EndDate = Datetime.newInstance(
          firstMonday.addDays(14),
          Time.newInstance(18, 0, 0, 0)
        )
      );

      // ---------------------------------------------------- 1. enquiry
      Lead enquiry = TestDataFactory.buildEnquiry(branch.Id);
      enquiry.Interested_Course__c = course.Id;
      insert enquiry;

      // ---------------------------------------------------- 2. conversion
      EnquiryConversionService.ConversionRequest conversion = new EnquiryConversionService.ConversionRequest();
      conversion.leadId = enquiry.Id;
      conversion.createGuardian = true;
      conversion.createApplication = true;
      EnquiryConversionService.ConversionResult converted = EnquiryConversionService.convert(
        conversion
      );
      Assert.isNotNull(converted.applicationId, 'Application created');
      Assert.isNotNull(converted.guardianId, 'Guardian created');
      Map<Id, Account> people = new Map<Id, Account>(
        [
          SELECT Id, PersonContactId
          FROM Account
          WHERE Id IN (:converted.learnerId, :converted.guardianId)
        ]
      );
      Id learnerContactId = people.get(converted.learnerId).PersonContactId;
      Id guardianContactId = people.get(converted.guardianId).PersonContactId;

      // ---------------------------------------------------- 3. application → offer → acceptance
      Id applicationId = converted.applicationId;
      for (DocumentChecklistItem item : [
        SELECT Id, IsRequired
        FROM DocumentChecklistItem
        WHERE ParentRecordId = :applicationId
      ]) {
        ApplicationService.updateChecklistItem(
          item.Id,
          item.IsRequired ? 'Accepted' : 'Waived',
          null
        );
      }
      ApplicationService.submitForReview(applicationId);
      ApplicationService.markReadyForDecision(applicationId);
      ApplicationService.decide(applicationId, 'Admit', null, 14);
      ApplicationService.respondToOffer(applicationId, true);
      Assert.areEqual(
        'Accepted',
        [
          SELECT Offer_Status__c
          FROM IndividualApplication
          WHERE Id = :applicationId
        ]
        .Offer_Status__c,
        'Offer accepted'
      );

      // ---------------------------------------------------- 4. enrolment with agreed price
      EnrolmentService.EnrolmentRequest enrolRequest = new EnrolmentService.EnrolmentRequest();
      enrolRequest.learnerAccountId = converted.learnerId;
      enrolRequest.offeringId = offering.Id;
      enrolRequest.applicationId = applicationId;
      Id enrolmentId = EnrolmentService.enrol(enrolRequest).enrolmentId;
      CourseOfferingParticipant enrolment = [
        SELECT ParticipationStatus, Agreed_Total__c
        FROM CourseOfferingParticipant
        WHERE Id = :enrolmentId
      ];
      Assert.areEqual('Enrolled', enrolment.ParticipationStatus, 'Enrolled');
      Assert.areEqual(11800, enrolment.Agreed_Total__c, '10,000 + 18% tax');
      Assert.areEqual(
        'Enrolled',
        [SELECT Status FROM IndividualApplication WHERE Id = :applicationId]
        .Status,
        'Application closed as enrolled'
      );

      // Each step is its own transaction in real use; a fresh governor context
      // for the operational half of the journey mirrors that.
      Test.startTest();

      // ---------------------------------------------------- 5. timetable
      SessionService.GenerationResult generated = SessionService.generate(
        offering.Id
      );
      Assert.isTrue(generated.created >= 2, 'Weekly sessions generated');
      Id todaySession = SessionService.addSession(
        offering.Id,
        System.now().addMinutes(-10),
        System.now().addMinutes(50),
        'Make-up',
        null
      );

      // ---------------------------------------------------- 6. attendance and 7. assessment (as the teacher)
      Course_Assessment__c assessment = new Course_Assessment__c(
        Name = 'Forces and motion',
        Course_Offering__c = offering.Id,
        Assessment_Type__c = 'Test',
        Max_Score__c = 40,
        Assessment_Date__c = Date.today()
      );
      insert assessment;
      System.runAs(teacher) {
        AttendanceService.Register register = AttendanceService.getRegister(
          todaySession
        );
        Assert.areEqual(1, register.rows.size(), 'Learner on the register');
        register.rows[0].status = 'Present';
        AttendanceService.saveRegister(todaySession, register.rows, 'Present');

        AssessmentService.Gradebook book = AssessmentService.getGradebook(
          assessment.Id
        );
        book.rows[0].score = 34;
        book.rows[0].feedback = 'Strong understanding of Newton\'s laws.';
        AssessmentService.saveResults(assessment.Id, book.rows);
        AssessmentService.publish(assessment.Id);
      }
      Assert.areEqual(
        100,
        [
          SELECT Attendance_Rate__c
          FROM CourseOfferingParticipant
          WHERE Id = :enrolmentId
        ]
        .Attendance_Rate__c,
        'Attendance recorded'
      );
      Assert.areEqual(
        'A',
        [
          SELECT Grade__c
          FROM Assessment_Result__c
          WHERE Learner__c = :learnerContactId
        ]
        .Grade__c,
        '34/40 = 85% is an A on the Standard scale'
      );

      // ---------------------------------------------------- 8. invoice to the fee payer
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      Student_Invoice__c invoice = [
        SELECT Name, Bill_To__c, Total__c, Status__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ];
      Assert.areEqual(guardianContactId, invoice.Bill_To__c, 'Guardian billed');
      Assert.areEqual(11800, invoice.Total__c, 'Invoice equals agreed price');

      // ---------------------------------------------------- 9. payment through the gateway, then reconciliation
      PaymentApi.PaymentNotification notice = new PaymentApi.PaymentNotification();
      notice.transactionId = 'journey-txn-1';
      notice.invoiceNumber = invoice.Name;
      notice.amount = 11800;
      notice.status = 'success';
      BillingService.PaymentResult paid = PaymentApi.process(notice);
      Assert.areEqual('Confirmed', paid.status, 'Payment confirmed');
      Assert.areEqual('Reconciled', paid.reconciliationStatus, 'Reconciled');
      Assert.areEqual(
        true,
        PaymentApi.process(notice).duplicate,
        'Gateway retry is idempotent'
      );

      Test.stopTest();

      // ---------------------------------------------------- outcome
      invoice = [
        SELECT Status__c, Balance_Due__c, Enrolment__r.Billing_Status__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ];
      Assert.areEqual('Paid', invoice.Status__c, 'Invoice paid');
      Assert.areEqual(0, invoice.Balance_Due__c, 'Nothing due');
      Assert.areEqual(
        'Paid',
        invoice.Enrolment__r.Billing_Status__c,
        'Enrolment paid'
      );
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Student_Payment__c
          WHERE Reconciliation_Status__c != 'Reconciled'
        ],
        'Every payment reconciled'
      );

      PortalService.Home home = PortalService.homeFor(guardianContactId);
      Assert.areEqual(1, home.learners.size(), 'Guardian sees the learner');
      Assert.areEqual(0, home.totalDue, 'Family owes nothing');
      PortalService.LearnerDetail detail = PortalService.learnerFor(
        guardianContactId,
        learnerContactId
      );
      Assert.areEqual(1, detail.results.size(), 'Published result visible');
      Assert.areEqual(1, detail.attendance.size(), 'Attendance visible');

      // The offer letter job was queued before the test boundary, so file it here.
      Assert.isNotNull(
        DocumentService.generate(applicationId, DocumentService.OFFER_LETTER),
        'Offer letter filed'
      );
      Assert.isNotNull(
        DocumentService.existing(invoiceId, DocumentService.INVOICE),
        'Invoice PDF filed'
      );
      Assert.isNotNull(
        DocumentService.existing(paid.paymentId, DocumentService.RECEIPT),
        'Receipt filed'
      );
    }
  }
}
