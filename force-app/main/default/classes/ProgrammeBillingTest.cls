@IsTest
private class ProgrammeBillingTest {
  private class Fixture {
    Programme_Enrolment__c enrolment;
  }

  @IsTest
  static void annualInvoiceSnapshotsPricesAndIsIdempotent() {
    System.runAs(TestDataFactory.admin()) {
      Fixture fixture = fixture('Full Annual Invoice');
      BillingService.deferredDocuments = new Set<Id>();
      Id invoiceId = BillingService.createProgrammeInvoice(
        fixture.enrolment.Id,
        1,
        'Annual'
      );
      System.assertEquals(
        invoiceId,
        BillingService.createProgrammeInvoice(fixture.enrolment.Id, 1, 'Annual')
      );
      Student_Invoice__c invoice = [
        SELECT
          Status__c,
          Programme_Enrolment__c,
          Year_Of_Study__c,
          Invoice_Kind__c,
          Programme_Invoice_Key__c,
          Enrolment__c,
          Subtotal__c,
          Tax_Total__c,
          Total__c
        FROM Student_Invoice__c
        WHERE Id = :invoiceId
      ];
      System.assertEquals('Issued', invoice.Status__c);
      System.assertEquals(fixture.enrolment.Id, invoice.Programme_Enrolment__c);
      System.assertEquals(null, invoice.Enrolment__c);
      System.assertEquals(1, invoice.Year_Of_Study__c);
      System.assertEquals('Annual', invoice.Invoice_Kind__c);
      System.assertEquals(105000, invoice.Subtotal__c);
      System.assertEquals(18900, invoice.Tax_Total__c);
      System.assertEquals(123900, invoice.Total__c);
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Enrolment_Fee_Line__c
          WHERE Programme_Enrolment__c = :fixture.enrolment.Id
        ]
      );
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Invoice_Line__c
          WHERE Student_Invoice__c = :invoiceId
        ]
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Student_Invoice__c
          WHERE Programme_Enrolment__c = :fixture.enrolment.Id
        ]
      );
    }
  }

  @IsTest
  static void admissionReleaseRuleSeparatesInvoiceKinds() {
    System.runAs(TestDataFactory.admin()) {
      Fixture fixture = fixture('Admission Fee');
      BillingService.deferredDocuments = new Set<Id>();
      Id annualId = BillingService.createProgrammeInvoice(
        fixture.enrolment.Id,
        1,
        'Annual'
      );
      Id admissionId = BillingService.createProgrammeInvoice(
        fixture.enrolment.Id,
        1,
        'Admission'
      );
      Map<String, Student_Invoice__c> byKind = new Map<String, Student_Invoice__c>();
      for (Student_Invoice__c row : [
        SELECT Invoice_Kind__c, Subtotal__c, Total__c
        FROM Student_Invoice__c
        WHERE Id IN :new Set<Id>{ annualId, admissionId }
      ])
        byKind.put(row.Invoice_Kind__c, row);
      System.assertEquals(100000, byKind.get('Annual').Subtotal__c);
      System.assertEquals(118000, byKind.get('Annual').Total__c);
      System.assertEquals(5000, byKind.get('Admission').Subtotal__c);
      System.assertEquals(5900, byKind.get('Admission').Total__c);
    }
  }

  @IsTest
  static void invalidKindAndMissingPricesAreRefused() {
    System.runAs(TestDataFactory.admin()) {
      Fixture fixture = fixture('Full Annual Invoice');
      try {
        BillingService.createProgrammeInvoice(fixture.enrolment.Id, 1, 'Term');
        System.assert(false, 'Expected invoice-kind validation.');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('Annual or Admission'));
      }
      try {
        BillingService.createProgrammeInvoice(
          fixture.enrolment.Id,
          2,
          'Annual'
        );
        System.assert(false, 'Expected missing year-two prices.');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('No active'));
      }
    }
  }

  private static Fixture fixture(String releaseRule) {
    TestDataFactory.createReferenceData();
    Learning learning = new Learning(
      Name = TestDataFactory.unique('Billing Programme'),
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram programme = new LearningProgram(
      Name = learning.Name,
      LearningId = learning.Id,
      Programme_Code__c = 'B',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Roll_Release_Rule__c = releaseRule,
      Active__c = true
    );
    insert programme;
    Branch__c campus = TestDataFactory.buildBranch();
    campus.Name = TestDataFactory.unique('Billing Campus');
    campus.Institution_Type__c = 'College';
    campus.Campus_Code__c = 'B';
    campus.Invoice_Prefix__c = 'CLG';
    campus.Invoice_Due_Days__c = 10;
    campus.Tax_Rate__c = 18;
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway';
    campus.Discounts_Allowed__c = false;
    insert campus;
    Learning courseLearning = new Learning(
      Name = TestDataFactory.unique('Billing Branch'),
      Type = 'LearningCourse',
      IsActive = true
    );
    insert courseLearning;
    LearningCourse branch = new LearningCourse(
      Name = courseLearning.Name,
      LearningId = courseLearning.Id,
      RecordTypeId = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName()
        .get('College_Branch')
        .getRecordTypeId(),
      External_ID__c = TestDataFactory.unique('BILL-CRS'),
      Programme__c = programme.Id,
      Branch_Code__c = 'BI',
      Curriculum_Version__c = '2025'
    );
    insert branch;
    insert new List<Fee_Price__c>{
      new Fee_Price__c(
        Learning_Course__c = branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Annual',
        Amount__c = 100000,
        Year_Of_Study__c = 1,
        Academic_Year__c = '2026-27',
        Effective_From__c = Date.today().addDays(-1)
      ),
      new Fee_Price__c(
        Learning_Course__c = branch.Id,
        Fee_Type__c = 'Admission',
        Billing_Frequency__c = 'One-time',
        Amount__c = 5000,
        Year_Of_Study__c = 1,
        Academic_Year__c = '2026-27',
        Effective_From__c = Date.today().addDays(-1)
      )
    };
    Campus_Branch__c intake = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = branch.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = 2,
      Intake_Lateral__c = 0,
      Admissions_Open__c = true
    );
    insert intake;
    Account student = PersonAccountService.buildPerson(
      'Billing',
      TestDataFactory.unique('Student'),
      null,
      null,
      campus.Id,
      'Learner'
    );
    insert student;
    student = [SELECT Id, PersonContactId FROM Account WHERE Id = :student.Id];
    IndividualApplication application = new IndividualApplication(
      Category = 'Education',
      AccountId = student.Id,
      ContactId = student.PersonContactId,
      Status = 'Processing',
      Branch__c = campus.Id,
      Learning_Course__c = branch.Id,
      Learning_Program__c = programme.Id,
      Campus_Branch__c = intake.Id,
      College_Mode__c = true,
      College_Stage__c = 'Fee Pending',
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1
    );
    insert application;
    Fixture result = new Fixture();
    result.enrolment = new Programme_Enrolment__c(
      Student__c = student.Id,
      Programme__c = programme.Id,
      Branch__c = branch.Id,
      Campus__c = campus.Id,
      Campus_Branch__c = intake.Id,
      Application__c = application.Id,
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1,
      Admission_Year__c = 2026,
      Academic_Year__c = '2026-27',
      Current_Year_Of_Study__c = 1,
      Status__c = 'Provisional',
      Payment_Due_By__c = Date.today().addDays(7)
    );
    insert result.enrolment;
    return result;
  }
}
