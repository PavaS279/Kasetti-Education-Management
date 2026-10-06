@IsTest
private class LmsIntegrationTest {
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'LMS-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Robotics LMS');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'One-time',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-30)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(Id = offering.Id, Name = 'Robotics LMS A');
      List<Account> learners = new List<Account>{
        PersonAccountService.buildPerson(
          'Asha',
          'Lms' + Crypto.getRandomInteger(),
          'asha.lms@example.com',
          null,
          branch.Id,
          'Learner'
        ),
        PersonAccountService.buildPerson(
          'Ravi',
          'Lms' + Crypto.getRandomInteger(),
          'ravi.lms@example.com',
          null,
          branch.Id,
          'Learner'
        )
      };
      insert learners;
      for (Account learner : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learner.Id;
        request.offeringId = offering.Id;
        EnrolmentService.enrol(request);
      }
    }
  }

  private static User integrationUser() {
    return TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Integration')
    );
  }

  private static CourseOffering offering() {
    return [SELECT Id FROM CourseOffering WHERE Name = 'Robotics LMS A'];
  }

  private static void request(String method, String path, String body) {
    RestRequest req = new RestRequest();
    req.httpMethod = method;
    Integer q = path.indexOf('?');
    String uri = q < 0 ? path : path.substring(0, q);
    req.requestURI = '/services/apexrest' + uri;
    if (q >= 0) {
      for (String pair : path.substring(q + 1).split('&')) {
        List<String> kv = pair.split('=');
        req.addParameter(kv[0], kv.size() > 1 ? kv[1] : '');
      }
    }
    if (body != null) {
      req.requestBody = Blob.valueOf(body);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
  }

  private static Map<String, Object> response() {
    return (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
  }

  @IsTest
  static void outboxRecordsClassAndEnrolmentChanges() {
    List<Integration_Event__c> events = [
      SELECT Event_Type__c, Record_Id__c, Payload__c, Status__c, Target__c
      FROM Integration_Event__c
      WHERE Target__c = 'LMS'
      ORDER BY Name
    ];
    Set<String> types = new Set<String>();
    for (Integration_Event__c e : events) {
      types.add(e.Event_Type__c);
      Assert.areEqual('Pending', e.Status__c, 'Pending');
    }
    Assert.isTrue(types.contains('class.updated'), 'Class event');
    Assert.isTrue(types.contains('enrolment.updated'), 'Enrolment events');
    Integer before = [SELECT COUNT() FROM Integration_Event__c];
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      update new CourseOffering(Id = offering().Id, EnrollmentCapacity = 12);
      update new CourseOffering(Id = offering().Id, Room__c = null);
      Test.stopTest();
    }
    Integration_Event__c latest = [
      SELECT Event_Type__c, Payload__c
      FROM Integration_Event__c
      ORDER BY Name DESC
      LIMIT 1
    ];
    Assert.areEqual(
      before + 1,
      [SELECT COUNT() FROM Integration_Event__c],
      'Only the capacity change is published'
    );
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      latest.Payload__c
    );
    Assert.areEqual(12, payload.get('capacity'), 'Snapshot');
    Assert.areEqual('LMS-01', payload.get('branchCode'), 'Branch code');
  }

  @IsTest
  static void outboxCanBeSwitchedOff() {
    AppSettings.overrides.put('LMS_Outbox', 'Off');
    Integer before = [SELECT COUNT() FROM Integration_Event__c];
    System.runAs(TestDataFactory.admin()) {
      update new CourseOffering(Id = offering().Id, EnrollmentCapacity = 14);
    }
    Assert.areEqual(
      before,
      [SELECT COUNT() FROM Integration_Event__c],
      'Nothing recorded'
    );
  }

  @IsTest
  static void lmsReadsClassesAndRoster() {
    Id classId = offering().Id;
    System.runAs(integrationUser()) {
      Test.startTest();
      request('GET', '/kem/v1/lms/classes?branch=lms-01', null);
      LmsApi.doGet();
      Assert.areEqual(200, RestContext.response.statusCode, 'OK');
      List<Object> classes = (List<Object>) response().get('classes');
      Assert.areEqual(1, classes.size(), 'Branch filter');
      Assert.areEqual(
        'Robotics LMS A',
        ((Map<String, Object>) classes[0]).get('name'),
        'Name'
      );

      request('GET', '/kem/v1/lms/classes?branch=NONE', null);
      LmsApi.doGet();
      Assert.areEqual(
        0,
        ((List<Object>) response().get('classes')).size(),
        'None'
      );

      request('GET', '/kem/v1/lms/classes/' + classId, null);
      LmsApi.doGet();
      Assert.areEqual('LMS-01', response().get('branchCode'), 'Detail');

      request('GET', '/kem/v1/lms/classes/' + classId + '/roster', null);
      LmsApi.doGet();
      List<Object> learners = (List<Object>) response().get('learners');
      Assert.areEqual(2, learners.size(), 'Roster');
      Assert.isNotNull(
        ((Map<String, Object>) learners[0]).get('email'),
        'Learner email visible to the integration user'
      );

      request('GET', '/kem/v1/lms/classes/not-an-id', null);
      LmsApi.doGet();
      Assert.areEqual(404, RestContext.response.statusCode, 'Bad id');

      request('GET', '/kem/v1/lms/unknown', null);
      LmsApi.doGet();
      Assert.areEqual(404, RestContext.response.statusCode, 'Unknown');

      request('GET', '/kem/v1/lms/classes?modifiedSince=yesterday', null);
      LmsApi.doGet();
      Assert.areEqual(400, RestContext.response.statusCode, 'Bad date');
      Test.stopTest();
    }
  }

  @IsTest
  static void lmsPollsAndAcknowledgesEvents() {
    System.runAs(integrationUser()) {
      Test.startTest();
      request('GET', '/kem/v1/lms/events?limit=1', null);
      LmsApi.doGet();
      Map<String, Object> page = response();
      List<Object> events = (List<Object>) page.get('events');
      Assert.areEqual(1, events.size(), 'Page size');
      Assert.isTrue((Boolean) page.get('hasMore'), 'More');
      String first = (String) page.get('next');

      request('GET', '/kem/v1/lms/events?after=' + first, null);
      LmsApi.doGet();
      List<Object> rest = (List<Object>) response().get('events');
      Assert.isFalse(rest.isEmpty(), 'Rest of the events');
      Map<String, Object> second = (Map<String, Object>) rest[0];
      Assert.isNotNull(second.get('payload'), 'Payload as JSON');

      request(
        'POST',
        '/kem/v1/lms/events/ack',
        JSON.serialize(
          new Map<String, Object>{ 'events' => new List<String>{ first } }
        )
      );
      LmsApi.doPost();
      Assert.areEqual(1, response().get('acknowledged'), 'Acknowledged');

      request(
        'POST',
        '/kem/v1/lms/events/ack',
        JSON.serialize(
          new Map<String, Object>{
            'events' => new List<String>{ (String) second.get('eventNumber') },
            'success' => false,
            'error' => 'Unknown course in LMS'
          }
        )
      );
      LmsApi.doPost();
      Test.stopTest();
      Assert.areEqual(
        'Delivered',
        [SELECT Status__c FROM Integration_Event__c WHERE Name = :first]
        .Status__c,
        'Delivered'
      );
      String secondNumber = (String) second.get('eventNumber');
      Integration_Event__c failed = [
        SELECT Status__c, Last_Error__c, Attempts__c
        FROM Integration_Event__c
        WHERE Name = :secondNumber
      ];
      Assert.areEqual('Failed', failed.Status__c, 'Failed');
      Assert.areEqual('Unknown course in LMS', failed.Last_Error__c, 'Error');
      Assert.areEqual(1, failed.Attempts__c, 'Attempts');
    }
  }

  @IsTest
  static void lmsPostsGradesIdempotently() {
    Id classId = offering().Id;
    List<CourseOfferingParticipant> roster = [
      SELECT ParticipantContactId, ParticipantContact.Email
      FROM CourseOfferingParticipant
      WHERE CourseOfferingId = :classId
      ORDER BY ParticipantContact.FirstName
    ];
    Map<String, Object> body = new Map<String, Object>{
      'classId' => classId,
      'assessment' => new Map<String, Object>{
        'externalId' => 'lms-quiz-1',
        'name' => 'Quiz 1',
        'type' => 'Quiz',
        'maxScore' => 20,
        'weight' => 10,
        'assessmentDate' => String.valueOf(Date.today())
      },
      'results' => new List<Object>{
        new Map<String, Object>{
          'learnerId' => roster[0].ParticipantContactId,
          'score' => 17
        },
        new Map<String, Object>{
          'learnerEmail' => roster[1].ParticipantContact.Email.toUpperCase(),
          'absent' => true
        }
      }
    };
    System.runAs(integrationUser()) {
      Test.startTest();
      request('POST', '/kem/v1/lms/grades', JSON.serialize(body));
      LmsApi.doPost();
      Assert.areEqual(201, RestContext.response.statusCode, 'Created');
      Assert.areEqual('Draft', response().get('status'), 'Draft');

      ((List<Object>) body.get('results')).remove(1);
      ((Map<String, Object>) ((List<Object>) body.get('results'))[0])
        .put('score', 18);
      body.put('publish', true);
      request('POST', '/kem/v1/lms/grades', JSON.serialize(body));
      LmsApi.doPost();
      Assert.areEqual(200, RestContext.response.statusCode, 'Updated');
      Assert.areEqual('Published', response().get('status'), 'Published');

      request('POST', '/kem/v1/lms/grades', JSON.serialize(body));
      LmsApi.doPost();
      Assert.areEqual(400, RestContext.response.statusCode, 'Locked');
      Assert.isTrue(
        ((String) response().get('error')).contains('published'),
        'Locked message'
      );
      Test.stopTest();
    }
    Course_Assessment__c assessment = [
      SELECT Status__c, Max_Score__c, Weight__c, Owner.Name
      FROM Course_Assessment__c
      WHERE External_Id__c = 'lms-quiz-1'
    ];
    Assert.areEqual('Published', assessment.Status__c, 'Published');
    Assessment_Result__c result = [
      SELECT Score__c, Grade__c
      FROM Assessment_Result__c
      WHERE Learner__c = :roster[0].ParticipantContactId
    ];
    Assert.areEqual(18, result.Score__c, 'Latest score');
    Assert.isNotNull(result.Grade__c, 'Graded at publication');
  }

  @IsTest
  static void lmsGradeValidation() {
    Id classId = offering().Id;
    System.runAs(integrationUser()) {
      Test.startTest();
      request('POST', '/kem/v1/lms/grades', '{not json');
      LmsApi.doPost();
      Assert.areEqual(400, RestContext.response.statusCode, 'Malformed');

      request(
        'POST',
        '/kem/v1/lms/grades',
        JSON.serialize(
          new Map<String, Object>{
            'classId' => classId,
            'assessment' => new Map<String, Object>{
              'externalId' => 'x',
              'name' => 'X',
              'maxScore' => 10
            },
            'results' => new List<Object>{
              new Map<String, Object>{
                'learnerEmail' => 'stranger@example.com',
                'score' => 5
              }
            }
          }
        )
      );
      LmsApi.doPost();
      Assert.areEqual(400, RestContext.response.statusCode, 'Unknown learner');
      Assert.isTrue(
        ((String) response().get('error')).contains('stranger@example.com'),
        'Named'
      );

      request(
        'POST',
        '/kem/v1/lms/grades',
        JSON.serialize(
          new Map<String, Object>{
            'classId' => classId,
            'assessment' => new Map<String, Object>{ 'name' => 'X' }
          }
        )
      );
      LmsApi.doPost();
      Assert.areEqual(400, RestContext.response.statusCode, 'No externalId');

      request('POST', '/kem/v1/lms/other', '{}');
      LmsApi.doPost();
      Assert.areEqual(404, RestContext.response.statusCode, 'Unknown');
      Test.stopTest();
    }
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Course_Assessment__c WHERE External_Id__c = 'x'],
      'Nothing saved'
    );
  }

  @IsTest
  static void otherUsersAreRefused() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      request('GET', '/kem/v1/lms/events', null);
      LmsApi.doGet();
      Assert.areEqual(403, RestContext.response.statusCode, 'Events refused');
      request('GET', '/kem/v1/lms/classes', null);
      LmsApi.doGet();
      Assert.areEqual(403, RestContext.response.statusCode, 'Classes refused');
    }
  }

  private class PushMock implements HttpCalloutMock {
    Integer status;
    String lastBody;
    PushMock(Integer status) {
      this.status = status;
    }
    public HttpResponse respond(HttpRequest req) {
      lastBody = req.getBody();
      Assert.areEqual('callout:KEM_LMS/events', req.getEndpoint(), 'Endpoint');
      HttpResponse res = new HttpResponse();
      res.setStatusCode(status);
      res.setBody(status == 200 ? '{}' : 'down');
      return res;
    }
  }

  @IsTest
  static void pushDeliversOrRecordsTheFailure() {
    Integer pending = [
      SELECT COUNT()
      FROM Integration_Event__c
      WHERE Target__c = 'LMS' AND Status__c = 'Pending'
    ];
    Test.setMock(HttpCalloutMock.class, new PushMock(503));
    Assert.areEqual(0, IntegrationService.push('LMS'), 'Nothing delivered');
    Assert.areEqual(
      pending,
      [SELECT COUNT() FROM Integration_Event__c WHERE Status__c = 'Failed'],
      'All failed with attempt counted'
    );
    PushMock ok = new PushMock(200);
    Test.setMock(HttpCalloutMock.class, ok);
    Test.startTest();
    AppSettings.overrides.put('LMS_Push', 'On');
    System.enqueueJob(new IntegrationService.SyncJob());
    Test.stopTest();
    Assert.areEqual(
      pending,
      [SELECT COUNT() FROM Integration_Event__c WHERE Status__c = 'Delivered'],
      'Delivered on retry'
    );
    Assert.areEqual(0, IntegrationService.backlog().get('LMS'), 'No backlog');
    new IntegrationSyncJob().execute(null);
  }

  @IsTest
  static void purgeRemovesOldEvents() {
    List<Integration_Event__c> events = [
      SELECT Id
      FROM Integration_Event__c
      LIMIT 2
    ];
    update new Integration_Event__c(Id = events[0].Id, Status__c = 'Delivered');
    Test.setCreatedDate(events[0].Id, System.now().addDays(-31));
    Test.setCreatedDate(events[1].Id, System.now().addDays(-31));
    Assert.areEqual(1, IntegrationService.purge(), 'Delivered and old only');
    Test.setCreatedDate(events[1].Id, System.now().addDays(-91));
    Assert.areEqual(1, IntegrationService.purge(), 'Undelivered after 90 days');
  }
}
