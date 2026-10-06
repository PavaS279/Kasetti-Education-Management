@IsTest
private class FinanceExportTest {
  /** Invoice 1,180 (1,000 + 18% tax), cash payment 1,180, withdrawal credit 200, refund 200 paid. */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    System.runAs(TestDataFactory.admin()) {
      IntegrationService.disabled = true;
      MessageService.disabled = true;
      Branch__c branch = TestDataFactory.buildBranch();
      branch.Branch_Code__c = 'ERP-01';
      branch.Invoice_Prefix__c = 'ERP';
      insert branch;
      LearningCourse course = TestDataFactory.createCourse('Accounts Course');
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
      Account learner = PersonAccountService.buildPerson(
        'Meera',
        'Ledger' + Crypto.getRandomInteger(),
        'meera.ledger@example.com',
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = offering.Id;
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
      payment.invoiceId = invoiceId;
      payment.amount = 1180;
      payment.method = 'Cash';
      payment.confirmed = true;
      BillingService.recordPayment(payment);
    }
  }

  private static Student_Invoice__c invoice() {
    return [
      SELECT Id, Name, Total__c, Tax_Total__c, Branch__c
      FROM Student_Invoice__c
      WHERE Branch__r.Branch_Code__c = 'ERP-01'
    ];
  }

  private static void creditAndRefund() {
    CreditService.CreditRequest credit = new CreditService.CreditRequest();
    credit.sourceInvoiceId = invoice().Id;
    credit.amount = 200;
    credit.origin = 'Withdrawal';
    credit.reason = 'Left early';
    Id noteId = CreditService.issueForInvoice(credit);
    AppSettings.overrides.put('Refund_Auto_Approve_Limit', '1000');
    CreditService.RefundRequest refund = new CreditService.RefundRequest();
    refund.creditNoteId = noteId;
    refund.amount = 200;
    refund.method = 'UPI';
    refund.reason = 'Withdrawal refund';
    Id refundId = CreditService.requestRefund(refund);
    CreditService.markRefundPaid(refundId, 'UPI-REF-1', Date.today());
  }

  @IsTest
  static void journalIsBalancedDoubleEntry() {
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      creditAndRefund();
      Test.startTest();
      FinanceExportService.Journal journal = FinanceExportService.journal(
        Date.today(),
        Date.today(),
        [SELECT Id FROM Branch__c WHERE Branch_Code__c = 'ERP-01'].Id
      );
      Test.stopTest();
      Assert.isTrue(journal.balanced, 'Debits equal credits');
      Assert.areEqual('ERP-01', journal.branchCode, 'Branch');
      Assert.areEqual(
        4,
        journal.documents,
        'Invoice, payment, credit note, refund'
      );
      Map<String, FinanceExportService.AccountTotal> accounts = new Map<String, FinanceExportService.AccountTotal>();
      for (FinanceExportService.AccountTotal total : journal.accounts) {
        accounts.put(total.account, total);
      }
      // Receivables: +1180 invoice, -1180 payment.
      Assert.areEqual(1180, accounts.get('1100').debit, 'AR debit');
      Assert.areEqual(1180, accounts.get('1100').credit, 'AR credit');
      Assert.areEqual(1000, accounts.get('4000').credit, 'Revenue net of tax');
      Assert.areEqual(180, accounts.get('2200').credit, 'Tax');
      Assert.areEqual(1180, accounts.get('1000').debit, 'Cash received');
      Assert.areEqual(200, accounts.get('4900').debit, 'Credit allowance');
      Assert.areEqual(200, accounts.get('2300').credit, 'Customer credit held');
      Assert.areEqual(
        200,
        accounts.get('2300').debit,
        'Customer credit refunded'
      );
      Assert.areEqual(200, accounts.get('1010').credit, 'Bank payout');
      String csv = FinanceExportService.toCsv(journal);
      Assert.isTrue(csv.startsWith('Entry ID,Date,Document Type'), 'Header');
      Assert.areEqual(
        journal.lines.size() + 1,
        csv.split('\r\n').size(),
        'One row per line'
      );
      Assert.isTrue(csv.contains('"UPI-REF-1"'), 'References quoted');
    }
  }

  @IsTest
  static void exportSavesTheFileAndRecord() {
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      FinanceExportService.ExportSummary summary = FinanceExportController.runExport(
        Date.today(),
        Date.today(),
        null
      );
      Test.stopTest();
      Assert.areEqual('Completed', summary.status, 'Completed');
      Assert.areEqual('Manual', summary.runType, 'Manual');
      Assert.isTrue(summary.lines >= 5, 'Lines: ' + summary.lines);
      Assert.areEqual(summary.totalDebit, summary.totalCredit, 'Balanced');
      ContentVersion file = [
        SELECT Title, VersionData
        FROM ContentVersion
        WHERE ContentDocumentId = :summary.fileId
      ];
      Assert.isTrue(file.Title.startsWith('KEM journal'), file.Title);
      Assert.isTrue(
        file.VersionData.toString().contains(invoice().Name),
        'Invoice in CSV'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :summary.exportId
        ],
        'File linked to the export'
      );
      Assert.areEqual(1, FinanceExportController.getRecent().size(), 'Listed');
      Assert.isFalse(
        FinanceExportController.getBranches().isEmpty(),
        'Branches'
      );
      FinanceExportService.Journal preview = FinanceExportController.preview(
        Date.today(),
        Date.today(),
        null
      );
      Assert.isTrue(preview.balanced, 'Preview balanced');
    }
  }

  @IsTest
  static void cancelledInvoiceIsReversed() {
    System.runAs(TestDataFactory.admin()) {
      MessageService.disabled = true;
      Branch__c branch = [
        SELECT Id
        FROM Branch__c
        WHERE Branch_Code__c = 'ERP-01'
      ];
      Account learner = PersonAccountService.buildPerson(
        'Kiran',
        'Ledger' + Crypto.getRandomInteger(),
        null,
        null,
        branch.Id,
        'Learner'
      );
      insert learner;
      EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
      request.learnerAccountId = learner.Id;
      request.offeringId = [
        SELECT Id
        FROM CourseOffering
        WHERE Branch__c = :branch.Id
      ]
      .Id;
      Test.startTest();
      Id enrolmentId = EnrolmentService.enrol(request).enrolmentId;
      Id invoiceId = BillingService.createInvoice(enrolmentId, true);
      BillingService.cancel(invoiceId, 'Raised in error');
      Test.stopTest();
      FinanceExportService.Journal journal = FinanceExportService.journal(
        Date.today(),
        Date.today(),
        branch.Id
      );
      Integer reversals = 0;
      Decimal reversed = 0;
      for (FinanceExportService.JournalLine line : journal.lines) {
        if (line.documentType == 'Invoice Cancellation') {
          reversals++;
          reversed += line.credit;
          Assert.isTrue(line.entryId.contains('-X-'), line.entryId);
        }
      }
      Assert.areEqual(3, reversals, 'Revenue, tax and receivable reversed');
      Assert.areEqual(1180, reversed, 'Receivable credited back');
      Assert.isTrue(journal.balanced, 'Still balanced');
    }
  }

  @IsTest
  static void journalValidatesTheRequest() {
    System.runAs(TestDataFactory.admin()) {
      List<String> messages = new List<String>();
      for (Integer i = 0; i < 3; i++) {
        try {
          if (i == 0) {
            FinanceExportService.journal(null, Date.today(), null);
          } else if (i == 1) {
            FinanceExportService.journal(
              Date.today(),
              Date.today().addDays(-1),
              null
            );
          } else {
            FinanceExportService.journal(
              Date.today().addDays(-100),
              Date.today(),
              null
            );
          }
        } catch (AppException e) {
          messages.add(e.getMessage());
        }
      }
      Assert.areEqual(3, messages.size(), String.join(messages, ' | '));
      Integer handled = 0;
      for (Integer i = 0; i < 2; i++) {
        try {
          if (i == 0) {
            FinanceExportController.preview(null, null, null);
          } else {
            FinanceExportController.runExport(
              Date.today(),
              Date.today().addDays(-1),
              null
            );
          }
        } catch (AuraHandledException e) {
          handled++;
        }
      }
      Assert.areEqual(2, handled, 'Controller reports errors');
      Assert.isTrue(messages[2].contains('92'), messages[2]);
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        FinanceExportService.journal(Date.today(), Date.today(), null);
        Assert.fail('Teachers cannot export');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
      try {
        FinanceExportController.getRecent();
        Assert.fail('Teachers cannot list exports');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Refused');
      }
    }
  }

  @IsTest
  static void csvNeutralisesFormulas() {
    Assert.areEqual(
      '"\'=SUM(A1)"',
      FinanceExportService.csv('=SUM(A1)'),
      'Formula'
    );
    Assert.areEqual(
      '"say ""hi"""',
      FinanceExportService.csv('say "hi"'),
      'Quotes'
    );
    Assert.areEqual('', FinanceExportService.csv(null), 'Null');
  }

  @IsTest
  static void dailyJobExportsYesterday() {
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      new FinanceExportJob().execute(null);
      Test.stopTest();
      Finance_Export__c record = [
        SELECT Run_Type__c, From_Date__c, To_Date__c, Status__c
        FROM Finance_Export__c
      ];
      Assert.areEqual('Scheduled', record.Run_Type__c, 'Scheduled');
      Assert.areEqual(
        Date.today().addDays(-1),
        record.From_Date__c,
        'Yesterday'
      );
      AppSettings.overrides.put('ERP_Daily_Export', 'Off');
      Assert.isNull(
        FinanceExportService.dailyExport(),
        'Off: nothing exported'
      );
    }
  }

  // ------------------------------------------------------------------ API

  private static void request(String method, String path, String body) {
    RestRequest req = new RestRequest();
    req.httpMethod = method;
    Integer q = path.indexOf('?');
    req.requestURI =
      '/services/apexrest' + (q < 0 ? path : path.substring(0, q));
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

  @IsTest
  static void erpApiServesJournalExportsAndEvents() {
    // Events for the ERP were switched off during setup; record one now.
    Student_Invoice__c inv = invoice();
    IntegrationService.financeDocuments(
      'invoice.issued',
      new List<SObject>{ inv }
    );
    User integration = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Integration')
    );
    String today = String.valueOf(Date.today());
    System.runAs(integration) {
      Test.startTest();
      request(
        'GET',
        '/kem/v1/erp/journal?from=' + today + '&to=' + today + '&branch=erp-01',
        null
      );
      ErpApi.doGet();
      Assert.areEqual(200, RestContext.response.statusCode, 'JSON journal');
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        RestContext.response.responseBody.toString()
      );
      Assert.isTrue((Boolean) body.get('balanced'), 'Balanced');

      request(
        'GET',
        '/kem/v1/erp/journal?from=' + today + '&to=' + today + '&format=csv',
        null
      );
      ErpApi.doGet();
      Assert.isTrue(
        RestContext.response.responseBody.toString().startsWith('Entry ID'),
        'CSV'
      );

      request('GET', '/kem/v1/erp/journal?from=nope', null);
      ErpApi.doGet();
      Assert.areEqual(400, RestContext.response.statusCode, 'Bad date');

      request(
        'GET',
        '/kem/v1/erp/journal?from=' + today + '&to=' + today + '&branch=NOPE',
        null
      );
      ErpApi.doGet();
      Assert.areEqual(400, RestContext.response.statusCode, 'Unknown branch');

      request(
        'POST',
        '/kem/v1/erp/exports',
        JSON.serialize(
          new Map<String, Object>{ 'fromDate' => today, 'toDate' => today }
        )
      );
      ErpApi.doPost();
      Assert.areEqual(201, RestContext.response.statusCode, 'Export created');

      request('GET', '/kem/v1/erp/exports', null);
      ErpApi.doGet();
      Assert.areEqual(200, RestContext.response.statusCode, 'Exports listed');

      request('GET', '/kem/v1/erp/events?limit=abc', null);
      ErpApi.doGet();
      Assert.areEqual(400, RestContext.response.statusCode, 'Bad limit');

      request('GET', '/kem/v1/erp/events', null);
      ErpApi.doGet();
      Map<String, Object> page = (Map<String, Object>) JSON.deserializeUntyped(
        RestContext.response.responseBody.toString()
      );
      Assert.areEqual(
        1,
        ((List<Object>) page.get('events')).size(),
        'ERP event'
      );

      request('GET', '/kem/v1/erp/other', null);
      ErpApi.doGet();
      Assert.areEqual(404, RestContext.response.statusCode, 'Unknown');
      request('POST', '/kem/v1/erp/other', '{}');
      ErpApi.doPost();
      Assert.areEqual(404, RestContext.response.statusCode, 'Unknown post');
      Test.stopTest();
    }
  }
}
