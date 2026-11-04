@IsTest
private class ProgrammeEnrolmentTriggerHandlerTest {
  private static final Id APPLICATION_ID = Id.valueOf('0iT000000000001');
  private static final Id STUDENT_ID = Id.valueOf('001000000000001');
  private static final Id PROGRAMME_ID = Id.valueOf('0jP000000000001');

  @IsTest
  static void insertBuildsKeysAndRequiresProvisional() {
    Programme_Enrolment__c valid = enrolment('Provisional');
    Programme_Enrolment__c invalid = enrolment('Enrolled');

    ProgrammeEnrolmentTriggerHandler.beforeInsert(
      new List<Programme_Enrolment__c>{ valid, invalid }
    );

    System.assertEquals(
      String.valueOf(APPLICATION_ID),
      valid.Application_Key__c
    );
    System.assertEquals(
      String.valueOf(STUDENT_ID) + '|' + String.valueOf(PROGRAMME_ID),
      valid.Active_Key__c
    );
    System.assertEquals(false, valid.hasErrors());
    System.assertEquals(true, invalid.hasErrors());
  }

  @IsTest
  static void updateEnforcesLifecycleAndImmutableIdentity() {
    Id rowId = Id.valueOf(
      Programme_Enrolment__c.SObjectType.getDescribe().getKeyPrefix() +
      '000000000001'
    );
    Programme_Enrolment__c oldValue = enrolment('Provisional');
    oldValue.Id = rowId;
    oldValue.Roll_Number__c = null;
    Programme_Enrolment__c enrolled = oldValue.clone(true, true, false, false);
    enrolled.Status__c = 'Enrolled';
    ProgrammeEnrolmentTriggerHandler.beforeUpdate(
      new List<Programme_Enrolment__c>{ enrolled },
      new Map<Id, Programme_Enrolment__c>{ rowId => oldValue }
    );
    System.assertEquals(false, enrolled.hasErrors());
    System.assertNotEquals(null, enrolled.Active_Key__c);

    Programme_Enrolment__c invalid = oldValue.clone(true, true, false, false);
    invalid.Status__c = 'Completed';
    invalid.Student__c = Id.valueOf('001000000000002');
    ProgrammeEnrolmentTriggerHandler.beforeUpdate(
      new List<Programme_Enrolment__c>{ invalid },
      new Map<Id, Programme_Enrolment__c>{ rowId => oldValue }
    );
    System.assertEquals(true, invalid.hasErrors());

    Programme_Enrolment__c enrolledOld = enrolment('Enrolled');
    enrolledOld.Id = rowId;
    enrolledOld.Roll_Number__c = 'KT26YBCS001';
    Programme_Enrolment__c completed = enrolledOld.clone(
      true,
      true,
      false,
      false
    );
    completed.Status__c = 'Completed';
    ProgrammeEnrolmentTriggerHandler.beforeUpdate(
      new List<Programme_Enrolment__c>{ completed },
      new Map<Id, Programme_Enrolment__c>{ rowId => enrolledOld }
    );
    System.assertEquals(Date.today(), completed.Completed_On__c);
    System.assertEquals(null, completed.Active_Key__c);

    Programme_Enrolment__c changedRoll = enrolledOld.clone(
      true,
      true,
      false,
      false
    );
    changedRoll.Roll_Number__c = 'KT26YBCS002';
    ProgrammeEnrolmentTriggerHandler.beforeUpdate(
      new List<Programme_Enrolment__c>{ changedRoll },
      new Map<Id, Programme_Enrolment__c>{ rowId => enrolledOld }
    );
    System.assertEquals(true, changedRoll.hasErrors());
  }

  @IsTest
  static void triggerRunsForPersistedLifecycle() {
    Learning learning = new Learning(
      Name = TestDataFactory.unique('PE Programme'),
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram programme = new LearningProgram(
      Name = learning.Name,
      LearningId = learning.Id,
      Programme_Code__c = 'P',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert programme;
    Branch__c campus = TestDataFactory.buildBranch();
    campus.Name = TestDataFactory.unique('PE Campus');
    campus.Institution_Type__c = 'College';
    campus.Campus_Code__c = 'P';
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque';
    campus.Discounts_Allowed__c = false;
    insert campus;
    Learning courseLearning = new Learning(
      Name = TestDataFactory.unique('PE Branch'),
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
      External_ID__c = TestDataFactory.unique('PE-CRS'),
      Programme__c = programme.Id,
      Branch_Code__c = 'PE',
      Curriculum_Version__c = '2025'
    );
    insert branch;
    Campus_Branch__c intake = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = branch.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = 1,
      Intake_Lateral__c = 0,
      Admissions_Open__c = true
    );
    insert intake;
    Account student = PersonAccountService.buildPerson(
      'Programme',
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
    Programme_Enrolment__c value = new Programme_Enrolment__c(
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
    insert value;
    value.Status__c = 'Enrolled';
    update value;
    value = [
      SELECT Status__c, Application_Key__c, Active_Key__c
      FROM Programme_Enrolment__c
      WHERE Id = :value.Id
    ];
    System.assertEquals('Enrolled', value.Status__c);
    System.assertEquals(
      String.valueOf(application.Id),
      value.Application_Key__c
    );
    System.assertNotEquals(null, value.Active_Key__c);
  }

  private static Programme_Enrolment__c enrolment(String status) {
    return new Programme_Enrolment__c(
      Application__c = APPLICATION_ID,
      Student__c = STUDENT_ID,
      Programme__c = PROGRAMME_ID,
      Status__c = status
    );
  }
}
