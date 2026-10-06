@IsTest
private class PaymentLinkTest {
  private static final String SECRET = 'test-webhook-secret';

  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      IntegrationService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'PAY-01';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Online Pay Course');
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
        5
      );
      Account learner = PersonAccountService.buildPerson(
        'Payal',
        'Online' + Crypto.getRandomInteger(),
        'payal.online@example.com',
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      BillingService.createInvoice(enrolmentId, true);
    }
  }

  private static Student_Invoice__c invoice() {
    return [
      SELECT Id, Name, Learner__c, Balance_Due__c, Status__c
      FROM Student_Invoice__c
      WHERE Branch__r.Branch_Code__c = 'PAY-01'
    ];
  }

  private static String sign(String body) {
    return EncodingUtil.convertToHex(
      Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(SECRET))
    );
  }

  private static void webhook(String body, String signature) {
    RestRequest req = new RestRequest();
    req.httpMethod = 'POST';
    req.requestURI = '/services/apexrest/kem/v1/payments/webhook';
    req.requestBody = Blob.valueOf(body);
    if (signature != null) {
      req.addHeader(PaymentWebhookApi.SIGNATURE_HEADER, signature);
    }
    RestContext.request = req;
    RestContext.response = new RestResponse();
  }

  @IsTest
  static void portalStartsALinkOnlyWhenEnabled() {
    Student_Invoice__c inv = invoice();
    PortalService.viewerOverride = inv.Learner__c;
    try {
      PortalController.startPayment(inv.Id);
      Assert.fail('Off by default');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('not available'), e.getMessage());
    }
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Test');
    Test.startTest();
    PaymentLinkService.LinkView link = PortalController.startPayment(inv.Id);
    PaymentLinkService.LinkView again = PortalController.startPayment(inv.Id);
    Test.stopTest();
    Assert.areEqual('Test', link.mode, 'Test mode');
    Assert.areEqual(inv.Balance_Due__c, link.amount, 'Balance due');
    Assert.isNull(link.token, 'Token is not shown in Test mode');
    Assert.isNull(link.checkoutUrl, 'No checkout in Test mode');
    Assert.areEqual(link.linkId, again.linkId, 'Active link reused');
    Assert.isTrue(
      PortalService.learnerFor(inv.Learner__c, inv.Learner__c).payOnline,
      'Portal shows Pay online'
    );
  }

  @IsTest
  static void portalUsersOnlyPayTheirOwnInvoices() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Test');
    Student_Invoice__c inv = invoice();
    System.runAs(TestDataFactory.admin()) {
      Account stranger = PersonAccountService.buildPerson(
        'Other',
        'Family' + Crypto.getRandomInteger(),
        null,
        null,
        null,
        'Guardian'
      );
      insert stranger;
      PortalService.viewerOverride = [
        SELECT PersonContactId
        FROM Account
        WHERE Id = :stranger.Id
      ]
      .PersonContactId;
    }
    try {
      PaymentLinkService.createForPortal(inv.Id);
      Assert.fail('Another family');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('not available'), e.getMessage());
    }
  }

  @IsTest
  static void liveLinkHasACheckoutAddress() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Live');
    AppSettings.overrides.put(
      'Payment_Checkout_URL',
      'https://pay.example.com/c?ref={token}&amount={amount}&inv={invoice}'
    );
    Student_Invoice__c inv = invoice();
    System.runAs(TestDataFactory.admin()) {
      PaymentLinkService.LinkView link = PaymentLinkController.createLink(
        inv.Id
      );
      Assert.isNotNull(link.token, 'Token for the gateway');
      Assert.isTrue(
        link.checkoutUrl.startsWith(
          'https://pay.example.com/c?ref=' + link.token
        ),
        link.checkoutUrl
      );
      Assert.isTrue(
        link.checkoutUrl.contains('&inv=' + inv.Name),
        link.checkoutUrl
      );
      PaymentLinkController.Panel panel = PaymentLinkController.getPanel(
        inv.Id
      );
      Assert.areEqual(1, panel.links.size(), 'Listed');
      Assert.areEqual('Live', panel.mode, 'Mode');
    }
    AppSettings.overrides.put(
      'Payment_Checkout_URL',
      'http://insecure.example.com'
    );
    try {
      PaymentLinkService.checkoutUrl('x', 1, 'INV');
      Assert.fail('HTTPS only');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('not configured'), e.getMessage());
    }
  }

  @IsTest
  static void signedWebhookRecordsThePaymentOnce() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Live');
    Student_Invoice__c inv = invoice();
    PaymentLinkService.LinkView link;
    System.runAs(TestDataFactory.admin()) {
      link = PaymentLinkService.createForStaff(inv.Id);
    }
    PaymentLinkService.secretOverride = SECRET;
    User integration = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Integration')
    );
    String body = JSON.serialize(
      new Map<String, Object>{
        'token' => link.token,
        'transactionId' => 'pay_ABC123',
        'amount' => inv.Balance_Due__c,
        'status' => 'success'
      }
    );
    System.runAs(integration) {
      Test.startTest();
      webhook(body, 'deadbeef');
      PaymentWebhookApi.receive();
      Assert.areEqual(401, RestContext.response.statusCode, 'Bad signature');

      webhook(body, sign(body));
      PaymentWebhookApi.receive();
      Assert.areEqual(
        200,
        RestContext.response.statusCode,
        RestContext.response.responseBody.toString()
      );
      Map<String, Object> first = (Map<String, Object>) JSON.deserializeUntyped(
        RestContext.response.responseBody.toString()
      );
      Assert.isFalse((Boolean) first.get('duplicate'), 'Recorded');

      webhook(body, sign(body).toUpperCase());
      PaymentWebhookApi.receive();
      Map<String, Object> second = (Map<String, Object>) JSON.deserializeUntyped(
        RestContext.response.responseBody.toString()
      );
      Assert.isTrue((Boolean) second.get('duplicate'), 'Repeat is a duplicate');
      Test.stopTest();
    }
    Payment_Link__c saved = [
      SELECT Status__c, Payment__c, Gateway_Reference__c
      FROM Payment_Link__c
      WHERE Id = :link.linkId
    ];
    Assert.areEqual('Paid', saved.Status__c, 'Paid');
    Assert.areEqual('pay_ABC123', saved.Gateway_Reference__c, 'Reference');
    Student_Payment__c payment = [
      SELECT Amount__c, Method__c, Status__c
      FROM Student_Payment__c
      WHERE Id = :saved.Payment__c
    ];
    Assert.areEqual('Online Gateway', payment.Method__c, 'Method');
    Assert.areEqual('Confirmed', payment.Status__c, 'Confirmed');
    Assert.areEqual('Paid', invoice().Status__c, 'Invoice paid');
  }

  @IsTest
  static void webhookRejectsBadRequests() {
    webhook('{}', null);
    PaymentWebhookApi.receive();
    Assert.areEqual(503, RestContext.response.statusCode, 'Not configured');
    PaymentLinkService.secretOverride = SECRET;
    String unknown = JSON.serialize(
      new Map<String, Object>{ 'token' => 'nope', 'transactionId' => 'x' }
    );
    webhook(unknown, sign(unknown));
    PaymentWebhookApi.receive();
    Assert.areEqual(400, RestContext.response.statusCode, 'Unknown link');
    String missing = JSON.serialize(
      new Map<String, Object>{ 'token' => 'nope' }
    );
    webhook(missing, sign(missing));
    PaymentWebhookApi.receive();
    Assert.areEqual(400, RestContext.response.statusCode, 'No transaction');
  }

  @IsTest
  static void failedPaymentsAndTooLargeAmounts() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Live');
    Student_Invoice__c inv = invoice();
    PaymentLinkService.LinkView link;
    System.runAs(TestDataFactory.admin()) {
      link = PaymentLinkService.createForStaff(inv.Id);
    }
    PaymentLinkService.Confirmation tooMuch = new PaymentLinkService.Confirmation();
    tooMuch.token = link.token;
    tooMuch.transactionId = 'pay_X';
    tooMuch.amount = inv.Balance_Due__c + 1;
    try {
      PaymentLinkService.confirm(tooMuch);
      Assert.fail('Too much');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('at most'), e.getMessage());
    }
    PaymentLinkService.Confirmation failed = new PaymentLinkService.Confirmation();
    failed.token = link.token;
    failed.transactionId = 'pay_F';
    failed.status = 'failed';
    Assert.areEqual(
      'Failed',
      PaymentLinkService.confirm(failed).status,
      'Failed'
    );
    Assert.areEqual(
      'Failed',
      [SELECT Status__c FROM Payment_Link__c WHERE Id = :link.linkId].Status__c,
      'Link failed'
    );
  }

  @IsTest
  static void testModeSimulationAndExpiry() {
    AppSettings.overrides.put('Payment_Gateway_Mode', 'Test');
    Student_Invoice__c inv = invoice();
    System.runAs(TestDataFactory.admin()) {
      PaymentLinkService.LinkView link = PaymentLinkService.createForStaff(
        inv.Id
      );
      Test.startTest();
      PaymentLinkController.simulate(link.linkId);
      Test.stopTest();
      Assert.areEqual(
        'Paid',
        [SELECT Status__c FROM Payment_Link__c WHERE Id = :link.linkId]
        .Status__c,
        'Simulated'
      );
      try {
        PaymentLinkService.createForStaff(inv.Id);
        Assert.fail('Nothing left to pay');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('nothing left'), e.getMessage());
      }
      AppSettings.overrides.put('Payment_Gateway_Mode', 'Live');
      try {
        PaymentLinkController.simulate(link.linkId);
        Assert.fail('Live cannot simulate');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Test mode'), e.getMessage());
      }
    }
    Payment_Link__c stale = new Payment_Link__c(
      Invoice__c = inv.Id,
      Amount__c = 10,
      Token__c = 'stale-token',
      Status__c = 'Active',
      Expires_On__c = System.now().addHours(-1)
    );
    insert stale;
    Assert.areEqual(1, PaymentLinkService.expireLinks(), 'Expired');
    Assert.areEqual(
      'Expired',
      [SELECT Status__c FROM Payment_Link__c WHERE Id = :stale.Id].Status__c,
      'Status'
    );
  }
}
