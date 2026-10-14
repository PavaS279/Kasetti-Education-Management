/** Shared college fixture: a Dean, a college campus, programme, branch, intake, annual fee and a passed admission. */
@IsTest
public class CollegeTestFactory {
  public class Fixture {
    public User dean;
    public IndividualApplication admission;
    public Campus_Branch__c intake;
    public LearningProgram programme;
    public LearningCourse branch;
    public Branch__c campus;
  }

  public static Fixture create(Integer capacity, Integer paymentWindowDays) {
    Fixture value = new Fixture();
    TestDataFactory.createReferenceData();
    value.dean = TestDataFactory.createUserWithLicense(
      new List<String>{
        'KEM_Administrator',
        'KEM_Administrator_Edu',
        'KEM_College_Dean'
      }
    );
    System.runAs(value.dean) {
      Learning learning = new Learning(
        Name = TestDataFactory.unique('College Programme'),
        Type = 'LearningProgram',
        IsActive = true
      );
      insert learning;
      value.programme = new LearningProgram(
        Name = learning.Name,
        LearningId = learning.Id,
        Programme_Code__c = 'A',
        Duration_Years__c = 2,
        Terms_Per_Year__c = 2,
        Term_Label__c = 'Semester',
        Qualification_Level__c = 'BE',
        Roll_Release_Rule__c = 'Full Annual Invoice',
        Payment_Window_Days__c = paymentWindowDays,
        Max_Backlogs_For_Promotion__c = 1,
        Active__c = true
      );
      insert value.programme;
      value.campus = TestDataFactory.buildBranch();
      value.campus.Name = TestDataFactory.unique('College Campus');
      value.campus.Institution_Type__c = 'College';
      value.campus.Campus_Code__c = 'A';
      value.campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway';
      value.campus.Discounts_Allowed__c = false;
      insert value.campus;
      Learning courseLearning = new Learning(
        Name = TestDataFactory.unique('College Branch'),
        Type = 'LearningCourse',
        IsActive = true
      );
      insert courseLearning;
      value.branch = new LearningCourse(
        Name = courseLearning.Name,
        LearningId = courseLearning.Id,
        RecordTypeId = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName()
          .get('College_Branch')
          .getRecordTypeId(),
        External_ID__c = TestDataFactory.unique('COLLEGE-CRS'),
        Programme__c = value.programme.Id,
        Branch_Code__c = 'AD',
        Curriculum_Version__c = '2025'
      );
      insert value.branch;
      insert new Fee_Price__c(
        Learning_Course__c = value.branch.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Annual',
        Amount__c = 100000,
        Academic_Year__c = '2026-27',
        Effective_From__c = Date.today().addDays(-1)
      );
      value.intake = new Campus_Branch__c(
        Campus__c = value.campus.Id,
        Branch__c = value.branch.Id,
        Academic_Year__c = '2026-27',
        Intake_Regular__c = capacity,
        Intake_Lateral__c = 0,
        Admissions_Open__c = true
      );
      insert value.intake;
      value.admission = admission(value, 'Applicant');
    }
    return value;
  }

  /** A further passed admission at Ready For Decision on the same intake. */
  public static IndividualApplication admission(
    Fixture fixture,
    String lastName
  ) {
    Account student = PersonAccountService.buildPerson(
      'College',
      TestDataFactory.unique(lastName),
      null,
      null,
      fixture.campus.Id,
      'Learner'
    );
    insert student;
    student = [SELECT Id, PersonContactId FROM Account WHERE Id = :student.Id];
    IndividualApplication value = new IndividualApplication(
      Category = 'Education',
      AccountId = student.Id,
      ContactId = student.PersonContactId,
      Status = 'Processing',
      Branch__c = fixture.campus.Id,
      Learning_Course__c = fixture.branch.Id,
      Learning_Program__c = fixture.programme.Id,
      Campus_Branch__c = fixture.intake.Id,
      College_Mode__c = true,
      College_Stage__c = 'Ready For Decision',
      Academic_Year__c = '2026-27',
      Entry_Route__c = 'Regular',
      Entry_Year_Of_Study__c = 1,
      Interview_Date__c = System.now().addHours(-1),
      Interviewer__c = fixture.dean.Id,
      Interview_Outcome__c = 'Pass'
    );
    insert value;
    return [
      SELECT Id, AccountId, ContactId, Branch__c, Learning_Course__c
      FROM IndividualApplication
      WHERE Id = :value.Id
    ];
  }

  /** The issued entry-year invoice of a programme enrolment. */
  public static Student_Invoice__c invoiceOf(Id enrolmentId) {
    return [
      SELECT Id, Total__c, Balance_Due__c, Status__c
      FROM Student_Invoice__c
      WHERE Programme_Enrolment__c = :enrolmentId AND Status__c != 'Cancelled'
      LIMIT 1
    ];
  }

  /** Records a payment; Online Gateway confirms at once, DD and cheque stay Pending. */
  public static BillingService.PaymentResult pay(
    Id invoiceId,
    Decimal amount,
    String method
  ) {
    BillingService.PaymentRequest payment = new BillingService.PaymentRequest();
    payment.invoiceId = invoiceId;
    payment.amount = amount;
    payment.method = method;
    if (method == 'Demand Draft' || method == 'Cheque') {
      payment.instrumentNumber = '004512';
      payment.instrumentBank = 'Canara Bank';
      payment.instrumentDate = Date.today();
    }
    return BillingService.recordPayment(payment);
  }

  /** Admits and pays the full annual invoice online: returns an Enrolled programme enrolment. */
  public static Id enrolPaid(Fixture fixture, IndividualApplication admission) {
    Id enrolmentId = InterviewService.admit(admission.Id);
    Student_Invoice__c invoice = invoiceOf(enrolmentId);
    pay(invoice.Id, invoice.Total__c, 'Online Gateway');
    return enrolmentId;
  }
}
