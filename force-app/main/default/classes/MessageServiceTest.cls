@IsTest
private class MessageServiceTest {
  /** Learner with a fee-paying mother (with email), enrolled in a class with a 7,080 price. */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Biology');
      insert new List<Fee_Price__c>{
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Admission',
          Billing_Frequency__c = 'One-time',
          Amount__c = 1000,
          Effective_From__c = Date.today().addDays(-10)
        ),
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Term',
          Amount__c = 5000,
          Effective_From__c = Date.today().addDays(-10)
        )
      };
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      Account learner = PersonAccountService.buildPerson(
        'Kabir',
        'Message' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      );
      Account guardian = PersonAccountService.buildPerson(
        'Meera',
        'Message' + Crypto.getRandomInteger(),
        'meera.parent@example.com',
        null,
        branch.Id,
        'Guardian'
      );
      insert new List<Account>{ learner, guardian };
      Map<Id, Account> people = new Map<Id, Account>(
        [
          SELECT Id, PersonContactId
          FROM Account
          WHERE Id IN :new List<Id>{ learner.Id, guardian.Id }
        ]
      );
      GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
      link.guardianContactId = people.get(guardian.Id).PersonContactId;
      link.learnerContactId = people.get(learner.Id).PersonContactId;
      link.relationship = 'Mother';
      GuardianRelationshipService.link(
        new List<GuardianRelationshipService.GuardianLink>{ link }
      );
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      EnrolmentService.enrol(request);
    }
  }

  private static CourseOfferingParticipant enrolment() {
    return [
      SELECT Id, ParticipantAccountId, ParticipantContactId, CourseOfferingId
      FROM CourseOfferingParticipant
      WHERE CourseOffering.LearningCourse.Name = 'Biology'
      LIMIT 1
    ];
  }

  private static Id guardianContact() {
    return [SELECT Id FROM Contact WHERE Email = 'meera.parent@example.com'].Id;
  }

  private static List<Message__c> messages(String event) {
    return [
      SELECT
        Channel__c,
        Status__c,
        Status_Detail__c,
        Subject__c,
        Body__c,
        Recipient__c,
        Learner_Account__c,
        Sent_By__c
      FROM Message__c
      WHERE Event__c = :event
      ORDER BY Channel__c
    ];
  }

  @IsTest
  static void invoiceAndPaymentNotificationsRespectConsent() {
    AppSettings.overrides.put('Email_Delivery', 'Live');
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Id guardianId = guardianContact();
      Test.startTest();
      Id invoiceId = BillingService.createInvoice(e.Id, true);
      List<Message__c> issued = messages('Invoice_Issued');
      Assert.areEqual(2, issued.size(), 'Email and portal');
      Assert.areEqual('Email', issued[0].Channel__c, 'Email first');
      Assert.areEqual('Queued', issued[0].Status__c, 'Queued for delivery');
      Assert.areEqual('Portal', issued[1].Channel__c, 'Portal inbox');
      Assert.areEqual('Delivered', issued[1].Status__c, 'Shown in portal');
      Assert.areEqual(guardianId, issued[0].Recipient__c, 'Fee payer');
      Assert.areEqual(
        e.ParticipantAccountId,
        issued[0].Learner_Account__c,
        'Learner'
      );
      String invoiceName = [
        SELECT Name
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ]
      .Name;
      Assert.isTrue(
        issued[0].Subject__c.contains(invoiceName),
        issued[0].Subject__c
      );
      Assert.isTrue(
        issued[0].Body__c.startsWith('Dear Meera,'),
        issued[0].Body__c
      );
      Assert.isTrue(issued[0].Body__c.contains('₹7,080.00'), issued[0].Body__c);
      Assert.isFalse(issued[0].Body__c.contains('{{'), 'All tokens merged');

      MessageService.invoicesIssued(new Set<Id>{ invoiceId });
      Assert.areEqual(2, messages('Invoice_Issued').size(), 'Never sent twice');

      MessageController.setEmailOptOut(
        e.ParticipantAccountId,
        guardianId,
        true
      );
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoiceId;
      payment.amount = 7080;
      payment.method = 'UPI';
      BillingService.recordPayment(payment);
      List<Message__c> receipts = messages('Payment_Received');
      Assert.areEqual('Suppressed', receipts[0].Status__c, 'Opted out');
      Assert.isTrue(
        receipts[0].Status_Detail__c.contains('opted out'),
        receipts[0].Status_Detail__c
      );
      Assert.areEqual(
        'Delivered',
        receipts[1].Status__c,
        'Portal still shows it'
      );
      Test.stopTest();

      Message__c delivered = messages('Invoice_Issued')[0];
      Assert.isTrue(
        delivered.Status__c == 'Sent' ||
        (delivered.Status__c == 'Failed' &&
        delivered.Status_Detail__c != null),
        'Delivery attempted: ' + delivered.Status__c
      );
    }
  }

  @IsTest
  static void remindersBeforeAndAfterTheDueDate() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Test.startTest();
      Id invoiceId = BillingService.createInvoice(e.Id, true);
      Date due = [
        SELECT Due_Date__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ]
      .Due_Date__c;
      Assert.areEqual(
        2,
        MessageService.sendReminders(due.addDays(-3)),
        'Due soon'
      );
      Assert.areEqual(
        0,
        MessageService.sendReminders(due.addDays(-3)),
        'Once only'
      );
      List<Message__c> soon = messages('Invoice_Due_Soon');
      Assert.areEqual('Not Sent', soon[0].Status__c, 'Email delivery is off');
      Assert.isTrue(
        soon[0].Status_Detail__c.contains('Email_Delivery'),
        'Explained'
      );

      Assert.areEqual(
        0,
        MessageService.sendReminders(due.addDays(5)),
        'Not a reminder day'
      );
      Assert.areEqual(
        2,
        MessageService.sendReminders(due.addDays(7)),
        'Seven days overdue'
      );
      Assert.isTrue(
        messages('Invoice_Overdue')[0].Subject__c.contains('7 days'),
        messages('Invoice_Overdue')[0].Subject__c
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void staffMessagesTimelineAndSessionCancellation() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Id guardianId = guardianContact();
      MessageService.StaffMessage request = new MessageService.StaffMessage();
      request.learnerAccountId = e.ParticipantAccountId;
      request.recipientId = guardianId;
      request.channel = 'Both';
      request.subject = 'Parent-teacher meeting';
      request.body = 'Please join us on Friday at 5 pm.';
      Assert.areEqual(
        2,
        MessageController.sendMessage(request).size(),
        'Email and portal'
      );
      Message__c staff = messages(MessageService.STAFF_EVENT)[0];
      Assert.areEqual(
        UserInfo.getUserId(),
        staff.Sent_By__c,
        'Sender recorded'
      );

      MessageService.Timeline timeline = MessageController.getTimeline(
        e.ParticipantAccountId
      );
      Assert.areEqual(2, timeline.messages.size(), 'On the learner timeline');
      Assert.areEqual(2, timeline.recipients.size(), 'Learner and mother');
      Boolean payerFound = false;
      for (MessageService.Recipient option : timeline.recipients) {
        if (option.contactId == guardianId) {
          payerFound = option.feePayer && option.role == 'Mother';
        }
      }
      Assert.isTrue(payerFound, 'Mother is the fee payer');
      Assert.isFalse(timeline.emailLive, 'Delivery off by default');

      Test.startTest();
      Id sessionId = SessionService.addSession(
        e.CourseOfferingId,
        System.now().addDays(2),
        System.now().addDays(2).addHours(1),
        'Make-up',
        null
      );
      SessionService.cancel(sessionId, 'Teacher unwell');
      List<Message__c> cancelled = messages('Session_Cancelled');
      Assert.areEqual(
        2,
        cancelled.size(),
        'Fee payer told by email and portal'
      );
      Assert.isTrue(
        cancelled[0].Body__c.contains('Teacher unwell'),
        cancelled[0].Body__c
      );
      Test.stopTest();
    }
  }

  @IsTest
  static void validationRenderingAndJobs() {
    System.runAs(TestDataFactory.admin()) {
      CourseOfferingParticipant e = enrolment();
      Contact stranger = new Contact(LastName = 'Stranger');
      insert stranger;
      Integer failures = 0;
      for (Integer i = 0; i < 6; i++) {
        MessageService.StaffMessage request = new MessageService.StaffMessage();
        request.learnerAccountId = i == 0 ? null : e.ParticipantAccountId;
        request.recipientId = i == 1 ? null : e.ParticipantContactId;
        request.subject = i == 2 ? null : 'Hello';
        request.body = 'Body';
        request.channel = i == 3 ? 'SMS' : 'Portal';
        if (i == 4) {
          request.recipientId = stranger.Id;
        }
        if (i == 5) {
          request.learnerAccountId = TestUtil.fakeId(Account.SObjectType);
        }
        try {
          MessageController.sendMessage(request);
        } catch (AuraHandledException ex) {
          failures++;
        }
      }
      Assert.areEqual(6, failures, 'Every rule enforced');
      try {
        MessageController.getTimeline(TestUtil.fakeId(Account.SObjectType));
        Assert.fail('Unknown learner');
      } catch (AuraHandledException ex) {
        Assert.isNotNull(ex.getMessage(), 'Reported');
      }
      try {
        MessageController.setEmailOptOut(
          e.ParticipantAccountId,
          TestUtil.fakeId(Contact.SObjectType),
          true
        );
        Assert.fail('Only the family');
      } catch (AuraHandledException ex) {
        Assert.isNotNull(ex.getMessage(), 'Reported');
      }

      Assert.areEqual('₹7,080.00', MessageService.money(7080), 'Two decimals');
      Assert.areEqual(
        'Hi Asha, Rs ',
        MessageService.render(
          'Hi {{Name}}, Rs {{Unknown}}',
          new Map<String, String>{ 'Name' => 'Asha' }
        ),
        'Unknown tokens are removed'
      );
      Assert.areEqual(
        0,
        MessageService.send(
            'No_Such_Template',
            new List<MessageService.Notice>()
          )
          .size(),
        'Unknown events are ignored'
      );

      Database.insert(
        new Message__c(
          Recipient__c = e.ParticipantContactId,
          Channel__c = 'Email',
          Status__c = 'Queued',
          Subject__c = 'Queued while delivery was live',
          Body__c = 'x'
        ),
        AccessLevel.SYSTEM_MODE
      );
      Test.startTest();
      Assert.areEqual(0, MessageService.dispatch(10), 'Delivery is off');
      Assert.areEqual(
        'Not Sent',
        [
          SELECT Status__c
          FROM Message__c
          WHERE Subject__c = 'Queued while delivery was live'
        ]
        .Status__c,
        'Recorded as not sent'
      );
      new MessageJob(true).execute(null);
      new MessageJob(false).execute(null);
      Test.stopTest();
      Assert.isTrue(
        KemJobs.jobFor('KEM Payment Reminders') instanceof MessageJob &&
        KemJobs.jobFor('KEM Message Dispatch') instanceof MessageJob,
        'Jobs registered'
      );
    }
  }
}
