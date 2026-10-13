@IsTest
private class CollegeFoundationTest {
  @IsTest
  static void stampsKeysAndCopiesSubjectDefaults() {
    Learning programmeLearning = new Learning(
      Name = 'BE',
      Type = 'LearningProgram',
      IsActive = true
    );
    insert programmeLearning;
    LearningProgram programme = new LearningProgram(
      Name = 'BE',
      LearningId = programmeLearning.Id,
      Programme_Code__c = 'B',
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert programme;

    Branch__c campus = TestDataFactory.buildBranch();
    campus.Name = 'Yelahanka Campus';
    campus.Institution_Type__c = 'College';
    campus.Campus_Code__c = ' y ';
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque;Online Gateway';
    campus.Discounts_Allowed__c = false;
    insert campus;
    campus = [
      SELECT Campus_Code__c, Campus_Code_Key__c
      FROM Branch__c
      WHERE Id = :campus.Id
    ];
    System.assertEquals('Y', campus.Campus_Code__c);
    System.assertEquals('Y', campus.Campus_Code_Key__c);

    LearningCourse course = createCollegeCourse('BE CSE', programme.Id, ' cs ');
    course = [
      SELECT Branch_Code__c, Branch_Code_Key__c
      FROM LearningCourse
      WHERE Id = :course.Id
    ];
    System.assertEquals('CS', course.Branch_Code__c);
    System.assertEquals(programme.Id + '|CS', course.Branch_Code_Key__c);

    Campus_Branch__c campusBranch = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = course.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = 120,
      Intake_Lateral__c = 12
    );
    insert campusBranch;
    campusBranch = [
      SELECT Unique_Key__c, Reserved_Regular__c, Finalised_Regular__c
      FROM Campus_Branch__c
      WHERE Id = :campusBranch.Id
    ];
    System.assertEquals(
      campus.Id + '|' + course.Id + '|2026-27',
      campusBranch.Unique_Key__c
    );
    System.assertEquals(0, campusBranch.Reserved_Regular__c);
    System.assertEquals(0, campusBranch.Finalised_Regular__c);
    assertValidationFailure(
      Database.update(
        new Campus_Branch__c(Id = campusBranch.Id, Reserved_Regular__c = -1),
        false
      ),
      'regular reserved and finalised seats must be non-negative'
    );
    assertValidationFailure(
      Database.update(
        new Campus_Branch__c(
          Id = campusBranch.Id,
          Reserved_Regular__c = 100,
          Finalised_Regular__c = 21
        ),
        false
      ),
      'cannot exceed regular intake'
    );
    assertValidationFailure(
      Database.update(
        new Campus_Branch__c(Id = campusBranch.Id, Reserved_Lateral__c = 13),
        false
      ),
      'cannot exceed lateral intake'
    );
    assertValidationFailure(
      Database.update(
        new Campus_Branch__c(
          Id = campusBranch.Id,
          Intake_Regular__c = 0,
          Intake_Lateral__c = 0
        ),
        false
      ),
      'open admissions require a positive regular or lateral intake'
    );

    Subject__c subject = new Subject__c(
      Name = 'Engineering Mathematics I',
      Branch__c = course.Id,
      Curriculum_Version__c = '2025',
      Subject_Code__c = ' 21mat11 ',
      Year_Of_Study__c = 1,
      Term__c = 1,
      Credits__c = 4,
      Internal_Max__c = 50,
      Exam_Max__c = 100,
      Internal_Pass_Percent__c = 40,
      Exam_Pass_Percent__c = 40,
      Total_Pass_Percent__c = 40
    );
    insert subject;
    subject = [
      SELECT Subject_Code__c, Unique_Key__c
      FROM Subject__c
      WHERE Id = :subject.Id
    ];
    System.assertEquals('21MAT11', subject.Subject_Code__c);
    assertValidationFailure(
      Database.insert(
        new Subject__c(
          Name = 'Beyond Programme Duration',
          Branch__c = course.Id,
          Curriculum_Version__c = '2025',
          Subject_Code__c = 'BAD5',
          Year_Of_Study__c = 5,
          Term__c = 9
        ),
        false
      ),
      'cannot exceed the programme duration'
    );
    assertValidationFailure(
      Database.insert(
        new Subject__c(
          Name = 'Beyond Programme Terms',
          Branch__c = course.Id,
          Curriculum_Version__c = '2025',
          Subject_Code__c = 'BAD9',
          Year_Of_Study__c = 1,
          Term__c = 9
        ),
        false
      ),
      'cannot exceed the programme term count'
    );

    CourseOffering section = new CourseOffering(
      Name = 'YLK BE-CSE 2026-27 Y1 A',
      RecordTypeId = collegeSectionRecordTypeId(),
      LearningCourseId = course.Id,
      Branch__c = campus.Id,
      Campus_Branch__c = campusBranch.Id,
      Academic_Year__c = '2026-27',
      Year_Of_Study__c = 1,
      Section_Code__c = 'A',
      EnrollmentCapacity = 60,
      Class_Status__c = 'Planned'
    );
    insert section;
    assertValidationFailure(
      Database.update(
        new CourseOffering(Id = section.Id, EnrollmentCapacity = 0),
        false
      ),
      'capacity must be greater than zero'
    );
    assertValidationFailure(
      Database.update(
        new CourseOffering(Id = section.Id, Year_Of_Study__c = 5),
        false
      ),
      'cannot exceed the programme duration'
    );
    section = [
      SELECT Section_Code__c, College_Section_Key__c
      FROM CourseOffering
      WHERE Id = :section.Id
    ];
    System.assertEquals('A', section.Section_Code__c);
    System.assertEquals(
      campusBranch.Id + '|2026-27|1|A',
      section.College_Section_Key__c
    );

    Database.SaveResult duplicateSection = Database.insert(
      new CourseOffering(
        Name = 'Duplicate Section A',
        RecordTypeId = collegeSectionRecordTypeId(),
        LearningCourseId = course.Id,
        Branch__c = campus.Id,
        Campus_Branch__c = campusBranch.Id,
        Academic_Year__c = '2026-27',
        Year_Of_Study__c = 1,
        Section_Code__c = ' a ',
        EnrollmentCapacity = 60,
        Class_Status__c = 'Planned'
      ),
      false
    );
    System.assertEquals(false, duplicateSection.isSuccess());
    System.assertEquals(
      StatusCode.DUPLICATE_VALUE,
      duplicateSection.getErrors()[0].getStatusCode()
    );

    Branch__c otherCampus = TestDataFactory.createBranch();
    LearningCourse otherSectionCourse = createCollegeCourse(
      'BE Civil',
      programme.Id,
      'CV'
    );
    List<Database.SaveResult> inconsistentSections = Database.insert(
      new List<CourseOffering>{
        new CourseOffering(
          Name = 'Wrong Campus',
          RecordTypeId = collegeSectionRecordTypeId(),
          LearningCourseId = course.Id,
          Branch__c = otherCampus.Id,
          Campus_Branch__c = campusBranch.Id,
          Academic_Year__c = '2026-27',
          Year_Of_Study__c = 1,
          Section_Code__c = 'C',
          EnrollmentCapacity = 60
        ),
        new CourseOffering(
          Name = 'Wrong College Branch',
          RecordTypeId = collegeSectionRecordTypeId(),
          LearningCourseId = otherSectionCourse.Id,
          Branch__c = campus.Id,
          Campus_Branch__c = campusBranch.Id,
          Academic_Year__c = '2026-27',
          Year_Of_Study__c = 1,
          Section_Code__c = 'D',
          EnrollmentCapacity = 60
        ),
        new CourseOffering(
          Name = 'Wrong Academic Year',
          RecordTypeId = collegeSectionRecordTypeId(),
          LearningCourseId = course.Id,
          Branch__c = campus.Id,
          Campus_Branch__c = campusBranch.Id,
          Academic_Year__c = '2027-28',
          Year_Of_Study__c = 1,
          Section_Code__c = 'E',
          EnrollmentCapacity = 60
        )
      },
      false
    );
    assertValidationFailure(inconsistentSections[0], 'campus must match');
    assertValidationFailure(inconsistentSections[1], 'does not offer');
    assertValidationFailure(
      inconsistentSections[2],
      'academic year must match'
    );

    Section_Subject__c assignment = new Section_Subject__c(
      Section__c = section.Id,
      Subject__c = subject.Id
    );
    insert assignment;
    assignment = [
      SELECT Term__c, Credits__c, Internal_Max__c, Exam_Max__c, Unique_Key__c
      FROM Section_Subject__c
      WHERE Id = :assignment.Id
    ];
    System.assertEquals(1, assignment.Term__c);
    System.assertEquals(4, assignment.Credits__c);
    System.assertEquals(50, assignment.Internal_Max__c);
    System.assertEquals(100, assignment.Exam_Max__c);
    System.assertEquals(
      section.Id + '|' + subject.Id + '|1',
      assignment.Unique_Key__c
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(Id = assignment.Id, Credits__c = -1),
        false
      ),
      'credits cannot be negative'
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(Id = assignment.Id, Internal_Max__c = -1),
        false
      ),
      'maximum marks cannot be negative'
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(Id = assignment.Id, Total_Pass_Percent__c = 101),
        false
      ),
      'pass percentages must be between 0 and 100'
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(Id = assignment.Id, Term__c = 2),
        false
      ),
      'term must match the catalogue subject term'
    );
    Room__c otherCampusRoom = TestDataFactory.createRoom(otherCampus.Id, 60);
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(
          Id = assignment.Id,
          Default_Room__c = otherCampusRoom.Id
        ),
        false
      ),
      'room from the same campus'
    );

    Room__c room = new Room__c(
      Name = 'College Room',
      Branch__c = campus.Id,
      Capacity__c = 60
    );
    insert room;
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(
          Id = assignment.Id,
          Status__c = 'Active',
          Default_Room__c = room.Id,
          Start_Date__c = Date.today(),
          End_Date__c = Date.today().addDays(30)
        ),
        false
      ),
      'assign faculty'
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(
          Id = assignment.Id,
          Status__c = 'Active',
          Faculty__c = UserInfo.getUserId(),
          Start_Date__c = Date.today(),
          End_Date__c = Date.today().addDays(30)
        ),
        false
      ),
      'assign a room'
    );
    assertValidationFailure(
      Database.update(
        new Section_Subject__c(
          Id = assignment.Id,
          Status__c = 'Active',
          Faculty__c = UserInfo.getUserId(),
          Default_Room__c = room.Id
        ),
        false
      ),
      'enter start and end dates'
    );
    update new Section_Subject__c(
      Id = assignment.Id,
      Status__c = 'Active',
      Faculty__c = UserInfo.getUserId(),
      Default_Room__c = room.Id,
      Start_Date__c = Date.today(),
      End_Date__c = Date.today().addDays(30)
    );

    LearningCourse otherCourse = createCollegeCourse(
      'BE Mechanical',
      programme.Id,
      'ME'
    );
    Subject__c otherBranchSubject = new Subject__c(
      Name = 'Mechanical Engineering Basics',
      Branch__c = otherCourse.Id,
      Curriculum_Version__c = '2025',
      Subject_Code__c = '21ME11',
      Year_Of_Study__c = 1,
      Term__c = 1
    );
    Subject__c wrongYearSubject = new Subject__c(
      Name = 'Engineering Mathematics III',
      Branch__c = course.Id,
      Curriculum_Version__c = '2025',
      Subject_Code__c = '21MAT31',
      Year_Of_Study__c = 2,
      Term__c = 3
    );
    insert new List<Subject__c>{ otherBranchSubject, wrongYearSubject };
    List<Database.SaveResult> invalidAssignments = Database.insert(
      new List<Section_Subject__c>{
        new Section_Subject__c(
          Section__c = section.Id,
          Subject__c = otherBranchSubject.Id
        ),
        new Section_Subject__c(
          Section__c = section.Id,
          Subject__c = wrongYearSubject.Id
        )
      },
      false
    );
    assertValidationFailure(invalidAssignments[0], 'same college branch');
    assertValidationFailure(invalidAssignments[1], 'year of study');

    update new CourseOffering(
      Id = section.Id,
      EnrollmentCapacity = 61,
      Section_Code__c = ' b '
    );
    section = [
      SELECT EnrollmentCapacity, Section_Code__c, College_Section_Key__c
      FROM CourseOffering
      WHERE Id = :section.Id
    ];
    System.assertEquals(61, section.EnrollmentCapacity);
    System.assertEquals('B', section.Section_Code__c);
    System.assertEquals(
      campusBranch.Id + '|2026-27|1|B',
      section.College_Section_Key__c
    );

    update new LearningCourse(Id = course.Id, Branch_Code__c = ' ce ');
    course = [
      SELECT Branch_Code__c, Branch_Code_Key__c
      FROM LearningCourse
      WHERE Id = :course.Id
    ];
    System.assertEquals('CE', course.Branch_Code__c);
    System.assertEquals(programme.Id + '|CE', course.Branch_Code_Key__c);

    update new Campus_Branch__c(
      Id = campusBranch.Id,
      Academic_Year__c = ' 2027-28 '
    );
    campusBranch = [
      SELECT Academic_Year__c, Unique_Key__c
      FROM Campus_Branch__c
      WHERE Id = :campusBranch.Id
    ];
    System.assertEquals('2027-28', campusBranch.Academic_Year__c);
    System.assert(campusBranch.Unique_Key__c.endsWith('|2027-28'));

    update new Branch__c(
      Id = campus.Id,
      Institution_Type__c = 'Learning Centre',
      Branch_Manager__c = UserInfo.getUserId()
    );
    campus = [SELECT Campus_Code_Key__c FROM Branch__c WHERE Id = :campus.Id];
    System.assertEquals(null, campus.Campus_Code_Key__c);
  }

  @IsTest
  static void keepsStandardProgrammesSeparateAndValidatesActiveCollegeProgrammes() {
    Learning standardLearning = new Learning(
      Name = 'Standard Programme',
      Type = 'LearningProgram',
      IsActive = true
    );
    insert standardLearning;
    LearningProgram standardProgramme = new LearningProgram(
      Name = 'Standard Programme',
      LearningId = standardLearning.Id
    );
    insert standardProgramme;
    standardProgramme = [
      SELECT Active__c
      FROM LearningProgram
      WHERE Id = :standardProgramme.Id
    ];
    System.assertEquals(false, standardProgramme.Active__c);

    LearningProgram programme = createProgramme('Active Programme', 'A');
    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Programme_Code__c = null),
        false
      ),
      'enter a programme code'
    );
    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Duration_Years__c = null),
        false
      ),
      'enter the duration and terms per year'
    );
    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Term_Label__c = null),
        false
      ),
      'select a term label'
    );
    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Qualification_Level__c = null),
        false
      ),
      'select a qualification level'
    );
    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Programme_Code__c = '1'),
        false
      ),
      'one uppercase letter'
    );
  }

  @IsTest
  static void rejectsInvalidSubjectGradingConfiguration() {
    LearningProgram programme = createProgramme('Subject Constraints', 'S');
    LearningCourse course = createCollegeCourse(
      'Subject Constraint Branch',
      programme.Id,
      'SC'
    );

    assertValidationFailure(
      Database.insert(
        new Subject__c(
          Name = 'Negative Credits',
          Branch__c = course.Id,
          Curriculum_Version__c = '2026',
          Subject_Code__c = 'NEGCR',
          Year_Of_Study__c = 1,
          Term__c = 1,
          Credits__c = -1
        ),
        false
      ),
      'credits cannot be negative'
    );
    assertValidationFailure(
      Database.insert(
        new Subject__c(
          Name = 'Invalid Pass Percentage',
          Branch__c = course.Id,
          Curriculum_Version__c = '2026',
          Subject_Code__c = 'BADPC',
          Year_Of_Study__c = 1,
          Term__c = 1,
          Total_Pass_Percent__c = 101
        ),
        false
      ),
      'pass percentages must be between 0 and 100'
    );
  }

  @IsTest
  static void rejectsInvalidProgrammeOperationalLimits() {
    LearningProgram programme = createProgramme('Programme Limits', 'L');

    assertValidationFailure(
      Database.update(
        new LearningProgram(Id = programme.Id, Payment_Window_Days__c = 0),
        false
      ),
      'payment window must be greater than zero'
    );
    assertValidationFailure(
      Database.update(
        new LearningProgram(
          Id = programme.Id,
          Max_Backlogs_For_Promotion__c = -1
        ),
        false
      ),
      'maximum backlogs for promotion cannot be negative'
    );
  }

  @IsTest
  static void rejectsDuplicateCampusBranchAndSubject() {
    Branch__c campus = TestDataFactory.createBranch();
    campus.Institution_Type__c = 'College';
    campus.Campus_Code__c = 'D';
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque';
    campus.Discounts_Allowed__c = false;
    update campus;
    assertValidationFailure(
      Database.update(
        new Branch__c(Id = campus.Id, Campus_Code__c = '1'),
        false
      ),
      'one uppercase letter'
    );
    assertValidationFailure(
      Database.update(
        new Branch__c(Id = campus.Id, Discounts_Allowed__c = true),
        false
      ),
      'discounts are not allowed'
    );
    LearningProgram programme = createProgramme('Duplicate Programme', 'D');
    LearningCourse course = createCollegeCourse(
      'Duplicate Test',
      programme.Id,
      'DT'
    );
    assertValidationFailure(
      Database.update(
        new LearningCourse(Id = course.Id, Branch_Code__c = '1'),
        false
      ),
      'two uppercase letters'
    );
    assertValidationFailure(
      Database.update(
        new LearningCourse(Id = course.Id, Curriculum_Version__c = null),
        false
      ),
      'enter the curriculum version'
    );
    Campus_Branch__c campusBranch = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = course.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = 10
    );
    insert campusBranch;
    Database.SaveResult duplicateCampusBranch = Database.insert(
      new Campus_Branch__c(
        Campus__c = campus.Id,
        Branch__c = course.Id,
        Academic_Year__c = '2026-27',
        Intake_Regular__c = 10
      ),
      false
    );
    System.assertEquals(false, duplicateCampusBranch.isSuccess());
    System.assertEquals(
      StatusCode.DUPLICATE_VALUE,
      duplicateCampusBranch.getErrors()[0].getStatusCode()
    );

    CourseOffering section = new CourseOffering(
      Name = 'Identifier Section',
      RecordTypeId = collegeSectionRecordTypeId(),
      LearningCourseId = course.Id,
      Branch__c = campus.Id,
      Campus_Branch__c = campusBranch.Id,
      Academic_Year__c = '2026-27',
      Year_Of_Study__c = 1,
      Section_Code__c = 'A',
      EnrollmentCapacity = 10
    );
    insert section;
    assertValidationFailure(
      Database.update(
        new CourseOffering(Id = section.Id, Section_Code__c = null),
        false
      ),
      'enter the section code'
    );
    assertValidationFailure(
      Database.update(
        new CourseOffering(Id = section.Id, Section_Code__c = 'A B'),
        false
      ),
      'uppercase letters, numbers, and hyphens'
    );

    Branch__c learningCentre = TestDataFactory.createBranch();
    List<Database.SaveResult> invalidCampusBranches = Database.insert(
      new List<Campus_Branch__c>{
        new Campus_Branch__c(
          Campus__c = learningCentre.Id,
          Branch__c = course.Id,
          Academic_Year__c = '2027-28',
          Intake_Regular__c = 10
        )
      },
      false
    );
    assertValidationFailure(
      invalidCampusBranches[0],
      'configured as a college'
    );

    assertValidationFailure(
      Database.insert(
        new Campus_Branch__c(
          Campus__c = campus.Id,
          Branch__c = course.Id,
          Academic_Year__c = '2026-29',
          Intake_Regular__c = 10
        ),
        false
      ),
      'consecutive academic year'
    );
    assertValidationFailure(
      Database.insert(
        new Fee_Price__c(
          Learning_Course__c = course.Id,
          Fee_Type__c = 'Tuition',
          Billing_Frequency__c = 'Annual',
          Amount__c = 1000,
          Effective_From__c = Date.today(),
          Academic_Year__c = '2026-29'
        ),
        false
      ),
      'academic year'
    );
    assertValidationFailure(
      Database.insert(
        new CourseOffering(
          Name = 'Invalid Academic Year',
          RecordTypeId = collegeSectionRecordTypeId(),
          LearningCourseId = course.Id,
          Branch__c = campus.Id,
          Campus_Branch__c = campusBranch.Id,
          Academic_Year__c = '2026-29',
          Year_Of_Study__c = 1,
          Section_Code__c = 'Z',
          EnrollmentCapacity = 10
        ),
        false
      ),
      'academic year'
    );

    Subject__c physics = new Subject__c(
      Name = 'Physics',
      Branch__c = course.Id,
      Curriculum_Version__c = '2025',
      Subject_Code__c = 'PHY1',
      Year_Of_Study__c = 1,
      Term__c = 1
    );
    insert physics;
    assertValidationFailure(
      Database.update(
        new Subject__c(Id = physics.Id, Subject_Code__c = 'BAD CODE'),
        false
      ),
      'uppercase letters, numbers, and hyphens'
    );
    Database.SaveResult duplicateSubject = Database.insert(
      new Subject__c(
        Name = 'Physics Again',
        Branch__c = course.Id,
        Curriculum_Version__c = '2025',
        Subject_Code__c = 'phy1',
        Year_Of_Study__c = 1,
        Term__c = 1
      ),
      false
    );
    System.assertEquals(false, duplicateSubject.isSuccess());
    System.assertEquals(
      StatusCode.DUPLICATE_VALUE,
      duplicateSubject.getErrors()[0].getStatusCode()
    );
  }

  private static LearningProgram createProgramme(String name, String code) {
    Learning learning = new Learning(
      Name = name,
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram programme = new LearningProgram(
      Name = name,
      LearningId = learning.Id,
      Programme_Code__c = code,
      Duration_Years__c = 4,
      Terms_Per_Year__c = 2,
      Term_Label__c = 'Semester',
      Qualification_Level__c = 'BE',
      Active__c = true
    );
    insert programme;
    return programme;
  }

  private static void assertValidationFailure(
    Database.SaveResult result,
    String expectedMessage
  ) {
    System.assertEquals(false, result.isSuccess());
    System.assertEquals(
      StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION,
      result.getErrors()[0].getStatusCode()
    );
    System.assert(
      result.getErrors()[0]
        .getMessage()
        .toLowerCase()
        .contains(expectedMessage.toLowerCase()),
      result.getErrors()[0].getMessage()
    );
  }

  private static LearningCourse createCollegeCourse(
    String name,
    Id programmeId,
    String branchCode
  ) {
    Learning learning = new Learning(
      Name = name,
      Type = 'LearningCourse',
      IsActive = true
    );
    insert learning;
    LearningCourse course = new LearningCourse(
      Name = name,
      LearningId = learning.Id,
      RecordTypeId = Schema.SObjectType.LearningCourse.getRecordTypeInfosByDeveloperName()
        .get('College_Branch')
        .getRecordTypeId(),
      External_ID__c = TestDataFactory.unique('CRS'),
      Programme__c = programmeId,
      Branch_Code__c = branchCode,
      Curriculum_Version__c = '2025'
    );
    insert course;
    return course;
  }

  private static Id collegeSectionRecordTypeId() {
    return Schema.SObjectType.CourseOffering.getRecordTypeInfosByDeveloperName()
      .get('College_Section')
      .getRecordTypeId();
  }
}
