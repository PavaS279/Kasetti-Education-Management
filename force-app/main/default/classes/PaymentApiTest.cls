@IsTest
private class PaymentApiTest {
  private static Id issuedInvoice() {
    TestDataFactory.createReferenceData();
    Branch__c branch = TestDataFactory.createBranch();
    LearningCourse course = TestDataFactory.createCourse('Chemistry');
    insert new Fee_Price__c(
      Learning_Course__c = course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = 1000,
      Effective_From__c = Date.today().addDays(-1)
    );
    Account learner = PersonAccountService.buildPerson(
      'Gate',
      'Way' + Crypto.getRandomInteger(),
      null,
      null,
      branch.Id,
      'Learner'
    );
    insert learner;
    EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
    request.learnerAccountId = learner.Id;
    request.offeringId = TestDataFactory.createOffering(course.Id, branch.Id, 5)
      .Id;
    return BillingService.createInvoice(
      EnrolmentService.enrol(request).enrolmentId,
      true
    );
  }

  private static Map<String, Object> post(Map<String, Object> body) {
    RestContext.request = new RestRequest();
    RestContext.request.requestURI = '/services/apexrest/kem/v1/payments';
    RestContext.request.httpMethod = 'POST';
    RestContext.request.requestBody = Blob.valueOf(JSON.serialize(body));
    RestContext.response = new RestResponse();
    PaymentApi.notifyPayment();
    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
    result.put('statusCode', RestContext.response.statusCode);
    return result;
  }

  @IsTest
  static void gatewayNotificationsAreIdempotent() {
    System.runAs(TestDataFactory.admin()) {
      Id invoiceId = issuedInvoice();
      String invoiceNumber = [
        SELECT Name
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ]
      .Name;
      Map<String, Object> pending = post(
        new Map<String, Object>{
          'transactionId' => 'txn_001',
          'invoiceNumber' => invoiceNumber,
          'amount' => 1180,
          'status' => 'pending'
        }
      );
      Assert.areEqual(201, pending.get('statusCode'), 'Created');
      Assert.areEqual('Pending', pending.get('status'), 'Pending');

      Map<String, Object> success = post(
        new Map<String, Object>{
          'transactionId' => 'txn_001',
          'invoiceNumber' => invoiceNumber,
          'amount' => 1180,
          'status' => 'success'
        }
      );
      Assert.areEqual(
        'Confirmed',
        success.get('status'),
        'Confirmed by later notice'
      );
      Assert.areEqual(
        'Reconciled',
        success.get('reconciliationStatus'),
        'Reconciled'
      );

      Map<String, Object> replay = post(
        new Map<String, Object>{
          'transactionId' => 'txn_001',
          'invoiceNumber' => invoiceNumber,
          'amount' => 1180,
          'status' => 'success'
        }
      );
      Assert.areEqual(200, replay.get('statusCode'), 'Replay is not a create');
      Assert.areEqual(true, replay.get('duplicate'), 'Duplicate flagged');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Student_Payment__c
          WHERE Gateway_Transaction_Id__c = 'txn_001'
        ],
        'One payment only'
      );
      Assert.areEqual(
        'Paid',
        [SELECT Status__c FROM Student_Invoice__c WHERE Id = :invoiceId]
        .Status__c,
        'Invoice paid once'
      );

      Map<String, Object> failed = post(
        new Map<String, Object>{
          'transactionId' => 'txn_002',
          'invoiceNumber' => invoiceNumber,
          'amount' => 50,
          'status' => 'failed'
        }
      );
      Assert.areEqual(
        'Failed',
        failed.get('status'),
        'Failed transaction recorded'
      );
    }
  }

  @IsTest
  static void rejectsInvalidNotifications() {
    System.runAs(TestDataFactory.admin()) {
      Assert.areEqual(
        400,
        post(new Map<String, Object>{ 'invoiceNumber' => 'X' })
          .get('statusCode'),
        'transactionId required'
      );
      Assert.areEqual(
        400,
        post(
            new Map<String, Object>{
              'transactionId' => 't',
              'invoiceNumber' => 'NOPE-1'
            }
          )
          .get('statusCode'),
        'Unknown invoice'
      );
      Assert.areEqual(
        400,
        post(
            new Map<String, Object>{
              'transactionId' => 't',
              'invoiceNumber' => 'X',
              'status' => 'odd'
            }
          )
          .get('statusCode'),
        'Bad status'
      );
      RestContext.request = new RestRequest();
      RestContext.request.requestBody = Blob.valueOf('{not json');
      RestContext.response = new RestResponse();
      PaymentApi.notifyPayment();
      Assert.areEqual(400, RestContext.response.statusCode, 'Malformed JSON');
    }
  }
}
