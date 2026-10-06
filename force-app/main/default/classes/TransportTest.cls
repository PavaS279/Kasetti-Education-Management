@IsTest
private class TransportTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'TRN-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Bus Maths');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Branch__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Monthly',
        Amount__c = 2000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      List<Account> learners = new List<Account>();
      for (String first : new List<String>{ 'Riya', 'Sam', 'Tara' }) {
        learners.add(
          PersonAccountService.buildPerson(
            first,
            'Rider',
            null,
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      for (Integer i = 0; i < 2; i++) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learners[i].Id;
        request.offeringId = offering.Id;
        EnrolmentService.enrol(request);
      }
      LearnerService.GuardianInput g = new LearnerService.GuardianInput();
      g.firstName = 'Meena';
      g.lastName = 'Rider';
      g.phone = '+919800011111';
      g.relationship = 'Mother';
      g.isFeePayer = true;
      g.portalAccess = true;
      LearnerService.addGuardian(learners[0].Id, g);
      Transport_Route__c route = new Transport_Route__c(
        Name = 'Route 1 – Lake View',
        Route_Code__c = 'TRN-R1',
        Branch__c = branch.Id,
        Capacity__c = 2,
        Monthly_Fee__c = 1200,
        Vehicle_Number__c = 'KA01AB1234',
        Driver_Name__c = 'Ravi Driver',
        Driver_Phone__c = '+919800022222',
        Morning_Start__c = '07:10'
      );
      insert route;
      insert new List<Transport_Stop__c>{
        new Transport_Stop__c(
          Route__c = route.Id,
          Name = 'Lake View Gate',
          Sequence__c = 1,
          Pickup_Time__c = '07:20',
          Drop_Time__c = '15:40'
        ),
        new Transport_Stop__c(
          Route__c = route.Id,
          Name = 'Market Circle',
          Sequence__c = 2,
          Pickup_Time__c = '07:35',
          Drop_Time__c = '15:25'
        )
      };
    }
  }

  private static Account learner(String first) {
    return [
      SELECT Id, PersonContactId
      FROM Account
      WHERE FirstName = :first AND LastName = 'Rider'
    ];
  }

  private static Transport_Route__c route() {
    return [
      SELECT Id, Seats_Taken__c
      FROM Transport_Route__c
      WHERE Route_Code__c = 'TRN-R1'
    ];
  }

  private static Transport_Stop__c stop(String name) {
    return [SELECT Id FROM Transport_Stop__c WHERE Name = :name];
  }

  private static TransportService.AssignRequest request(
    String first,
    String stopName
  ) {
    TransportService.AssignRequest r = new TransportService.AssignRequest();
    r.learnerAccountId = learner(first).Id;
    r.routeId = route().Id;
    r.stopId = stop(stopName).Id;
    r.direction = 'Both ways';
    r.startDate = Date.today();
    return r;
  }

  @IsTest
  static void assignAddsFeeLineSeatAndManifest() {
    System.runAs(TestDataFactory.admin()) {
      Id assignmentId = TransportController.assign(
        request('Riya', 'Lake View Gate')
      );
      Transport_Assignment__c a = [
        SELECT
          Status__c,
          Monthly_Fee__c,
          Fee_Line__r.Fee_Type__c,
          Fee_Line__r.Billing_Frequency__c,
          Fee_Line__r.Line_Total__c,
          Fee_Line__r.Next_Bill_Date__c,
          Fee_Line__r.Periods_Billed__c,
          Enrolment__c
        FROM Transport_Assignment__c
        WHERE Id = :assignmentId
      ];
      Assert.areEqual('Active', a.Status__c, 'Active');
      Assert.areEqual('Transport', a.Fee_Line__r.Fee_Type__c, 'Transport fee');
      Assert.areEqual('Monthly', a.Fee_Line__r.Billing_Frequency__c, 'Monthly');
      Assert.areEqual(1200, a.Fee_Line__r.Line_Total__c, 'Route fee');
      Assert.areEqual(
        Date.today(),
        a.Fee_Line__r.Next_Bill_Date__c,
        'Billed from the start'
      );
      Assert.isNotNull(a.Enrolment__c, 'Billed with the class enrolment');
      Assert.areEqual(1, route().Seats_Taken__c, 'Seat taken');

      List<TransportService.RouteSummary> routes = TransportController.getRoutes(
        null
      );
      Assert.areEqual(1, routes.size(), 'One route');
      Assert.areEqual(2, routes[0].stops, 'Two stops');
      Assert.isTrue(
        routes[0].fillRate == 50,
        'Half full: ' + routes[0].fillRate
      );

      TransportService.RouteDetail detail = TransportController.getRoute(
        route().Id
      );
      Assert.isTrue(detail.canManage, 'Admin manages');
      Assert.areEqual('Lake View Gate', detail.stops[0].name, 'Stops in order');
      Assert.areEqual(
        1,
        detail.stops[0].riders.size(),
        'Riya at the first stop'
      );
      Assert.areEqual(
        'Meena Rider',
        detail.stops[0].riders[0].guardian,
        'Fee payer on the manifest'
      );
      Assert.areEqual(
        '+919800011111',
        detail.stops[0].riders[0].guardianPhone,
        'Phone'
      );

      List<TransportService.LearnerOption> options = TransportController.searchLearners(
        route().Id,
        'Rider'
      );
      Assert.areEqual(
        2,
        options.size(),
        'Only enrolled learners of the branch'
      );
      for (TransportService.LearnerOption o : options) {
        if (o.name.startsWith('Riya')) {
          Assert.areEqual(
            'Route 1 – Lake View',
            o.currentRoute,
            'Current route shown'
          );
        }
      }

      TransportController.changeStop(assignmentId, stop('Market Circle').Id);
      List<TransportService.TransportItem> portal = TransportService.forLearners(
        new Set<Id>{ learner('Riya').Id }
      );
      Assert.areEqual('Market Circle', portal[0].stop, 'Stop changed');
      Assert.areEqual('07:35', portal[0].pickupTime, 'Pick-up time');
      Assert.areEqual('Ravi Driver', portal[0].driver, 'Driver');
    }
  }

  @IsTest
  static void rulesAreEnforced() {
    System.runAs(TestDataFactory.admin()) {
      TransportController.assign(request('Riya', 'Lake View Gate'));
      List<TransportService.AssignRequest> bad = new List<TransportService.AssignRequest>();
      bad.add(request('Riya', 'Market Circle'));
      TransportService.AssignRequest past = request('Sam', 'Lake View Gate');
      past.startDate = Date.today().addDays(-1);
      bad.add(past);
      TransportService.AssignRequest notEnrolled = request(
        'Tara',
        'Lake View Gate'
      );
      bad.add(notEnrolled);
      TransportService.AssignRequest direction = request(
        'Sam',
        'Lake View Gate'
      );
      direction.direction = 'Sideways';
      bad.add(direction);
      List<String> expected = new List<String>{
        'already rides',
        'past',
        'no active enrolment',
        'Both ways'
      };
      for (Integer i = 0; i < bad.size(); i++) {
        try {
          TransportService.assign(bad[i]);
          Assert.fail('Expected ' + expected[i]);
        } catch (AppException e) {
          Assert.isTrue(e.getMessage().contains(expected[i]), e.getMessage());
        }
      }
      // Without a fee no enrolment is needed; the route is then full.
      notEnrolled.chargeFee = false;
      Id free = TransportService.assign(notEnrolled);
      Assert.isNull(
        [SELECT Fee_Line__c FROM Transport_Assignment__c WHERE Id = :free]
        .Fee_Line__c,
        'No fee line'
      );
      try {
        TransportService.assign(request('Sam', 'Lake View Gate'));
        Assert.fail('Full');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('is full'), e.getMessage());
      }
      try {
        TransportController.notifyRoute(route().Id, 'x');
        Assert.fail('Message needed');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Write the message'),
          e.getMessage()
        );
      }
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        TransportService.assign(request('Sam', 'Lake View Gate'));
        Assert.fail('Teachers cannot manage transport');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
  }

  @IsTest
  static void feeIsBilledMonthlyUntilTheEndDate() {
    System.runAs(TestDataFactory.admin()) {
      Id assignmentId = TransportService.assign(
        request('Riya', 'Lake View Gate')
      );
      Transport_Assignment__c a = [
        SELECT Enrolment__c, Fee_Line__c
        FROM Transport_Assignment__c
        WHERE Id = :assignmentId
      ];
      Date start = Date.today();
      BillingService.billDuePeriods(a.Enrolment__c, start);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Invoice_Line__c
          WHERE Enrolment_Fee_Line__c = :a.Fee_Line__c
        ],
        'First transport month billed'
      );
      // Ends after the second month has started: billed up to then, not after.
      TransportController.endAssignment(
        assignmentId,
        start.addMonths(1).addDays(3),
        'Moved house'
      );
      Enrolment_Fee_Line__c line = [
        SELECT Bill_Until__c, Invoiced__c
        FROM Enrolment_Fee_Line__c
        WHERE Id = :a.Fee_Line__c
      ];
      Assert.areEqual(
        start.addMonths(1).addDays(3),
        line.Bill_Until__c,
        'Bill until the end'
      );
      Assert.isFalse(line.Invoiced__c, 'A month still to bill');
      Assert.areEqual(0, route().Seats_Taken__c, 'Seat released');
      Test.startTest();
      BillingService.billDuePeriods(a.Enrolment__c, start.addMonths(3));
      Test.stopTest();
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Invoice_Line__c
          WHERE Enrolment_Fee_Line__c = :a.Fee_Line__c
        ],
        'Second month billed, nothing after the end'
      );
      Assert.isTrue(
        [
          SELECT Invoiced__c
          FROM Enrolment_Fee_Line__c
          WHERE Id = :a.Fee_Line__c
        ]
        .Invoiced__c,
        'Line closed'
      );
      Transport_Assignment__c ended = [
        SELECT Status__c, Notes__c
        FROM Transport_Assignment__c
        WHERE Id = :assignmentId
      ];
      Assert.areEqual('Ended', ended.Status__c, 'Ended');
      Assert.isTrue(ended.Notes__c.contains('Moved house'), 'Reason kept');
      try {
        TransportService.endAssignment(assignmentId, null, null);
        Assert.fail('Already ended');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('not active'), e.getMessage());
      }
    }
  }

  @IsTest
  static void endingBeforeTheNextMonthClosesTheFeeAndJobBillsTransport() {
    System.runAs(TestDataFactory.admin()) {
      TransportService.AssignRequest r = request('Sam', 'Lake View Gate');
      r.startDate = Date.today().addDays(1);
      Id assignmentId = TransportService.assign(r);
      Id lineId = [
        SELECT Fee_Line__c
        FROM Transport_Assignment__c
        WHERE Id = :assignmentId
      ]
      .Fee_Line__c;
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM CourseOfferingParticipant
          WHERE
            Id IN (
              SELECT Enrolment__c
              FROM Enrolment_Fee_Line__c
              WHERE Fee_Type__c = 'Transport' AND Periods_Billed__c = 0
            )
        ],
        'Transport line waits for its start date'
      );
      TransportService.endAssignment(assignmentId, Date.today(), null);
      Assert.isTrue(
        [SELECT Invoiced__c FROM Enrolment_Fee_Line__c WHERE Id = :lineId]
        .Invoiced__c,
        'Ended before it started: nothing to bill'
      );
    }
  }

  @IsTest
  static void familiesOnARouteAreMessaged() {
    System.runAs(TestDataFactory.admin()) {
      TransportService.assign(request('Riya', 'Lake View Gate'));
      Test.startTest();
      Integer sent = TransportController.notifyRoute(
        route().Id,
        'The bus is 20 minutes late today.'
      );
      Test.stopTest();
      Assert.isTrue(sent >= 1, 'The family is messaged: ' + sent);
      Message__c m = [
        SELECT Subject__c, Body__c
        FROM Message__c
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      Assert.isTrue(m.Subject__c.contains('Route 1'), m.Subject__c);
      Assert.isTrue(m.Body__c.contains('20 minutes late'), m.Body__c);
    }
  }

  @IsTest
  static void nightlyJobBillsTransportFromItsStart() {
    System.runAs(TestDataFactory.admin()) {
      Id assignmentId = TransportService.assign(
        request('Sam', 'Lake View Gate')
      );
      Id lineId = [
        SELECT Fee_Line__c
        FROM Transport_Assignment__c
        WHERE Id = :assignmentId
      ]
      .Fee_Line__c;
      Test.startTest();
      RecurringBillingJob.run();
      Test.stopTest();
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Invoice_Line__c
          WHERE Enrolment_Fee_Line__c = :lineId
        ],
        'Transport billed by the job without a manual first invoice'
      );
    }
  }

  @IsTest
  static void controllerReportsErrors() {
    System.runAs(TestDataFactory.admin()) {
      Integer failures = 0;
      try {
        TransportController.getRoute(null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        TransportController.assign(null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        TransportController.changeStop(null, null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        TransportController.endAssignment(null, null, null);
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        TransportController.searchLearners(null, 'Rider');
      } catch (AuraHandledException e) {
        failures++;
      }
      try {
        TransportController.notifyRoute(null, 'The bus is late today');
      } catch (AuraHandledException e) {
        failures++;
      }
      Assert.areEqual(6, failures, 'Every error reported');
      Assert.isTrue(
        TransportController.searchLearners(route().Id, 'R').isEmpty(),
        'Two letters needed'
      );
    }
  }
}
