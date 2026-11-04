@IsTest
private class CollegeCatalogTest {
  @IsTest
  static void returnsCollegeCatalogueWithAppSpecificRows() {
    User admin = TestDataFactory.admin();
    Learning learning = new Learning(
      Name = 'BE',
      Type = 'LearningProgram',
      IsActive = true
    );
    insert learning;
    LearningProgram programme = new LearningProgram(
      Name = 'Bachelor of Engineering',
      LearningId = learning.Id,
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
    campus.Campus_Code__c = 'Y';
    campus.Allowed_Payment_Methods__c = 'Demand Draft;Cheque';
    campus.Discounts_Allowed__c = false;
    insert campus;

    Learning courseLearning = new Learning(
      Name = 'BE CSE',
      Type = 'LearningCourse',
      IsActive = true
    );
    insert courseLearning;
    LearningCourse branch = new LearningCourse(
      Name = 'Computer Science and Engineering',
      LearningId = courseLearning.Id,
      RecordTypeId = recordTypeId(LearningCourse.SObjectType, 'College_Branch'),
      External_ID__c = TestDataFactory.unique('CSE'),
      Programme__c = programme.Id,
      Branch_Code__c = 'CS',
      Curriculum_Version__c = '2025'
    );
    insert branch;
    Campus_Branch__c campusBranch = new Campus_Branch__c(
      Campus__c = campus.Id,
      Branch__c = branch.Id,
      Academic_Year__c = '2026-27',
      Intake_Regular__c = 120,
      Intake_Lateral__c = 12
    );
    insert campusBranch;
    Subject__c subject = new Subject__c(
      Name = 'Engineering Mathematics I',
      Branch__c = branch.Id,
      Curriculum_Version__c = '2025',
      Subject_Code__c = '21MAT11',
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
    CourseOffering section = new CourseOffering(
      Name = 'YLK BE-CSE 2026-27 Y1 A',
      RecordTypeId = recordTypeId(
        CourseOffering.SObjectType,
        'College_Section'
      ),
      LearningCourseId = branch.Id,
      Branch__c = campus.Id,
      Campus_Branch__c = campusBranch.Id,
      Academic_Year__c = '2026-27',
      Year_Of_Study__c = 1,
      Section_Code__c = 'A',
      EnrollmentCapacity = 60,
      Class_Status__c = 'Planned'
    );
    insert section;
    Section_Subject__c sectionSubject = new Section_Subject__c(
      Section__c = section.Id,
      Subject__c = subject.Id
    );
    insert sectionSubject;

    CollegeCatalogService.Dashboard result;
    System.runAs(admin) {
      Test.startTest();
      result = CollegeCatalogController.getDashboard();
      Test.stopTest();
    }
    System.assertEquals(1, result.campuses.size());
    System.assertEquals('Yelahanka Campus', result.campuses[0].name);
    System.assertEquals(1, result.programmes.size());
    System.assertEquals(1, result.branches.size());
    System.assertEquals('CS', result.branches[0].status);
    System.assertEquals(132, result.campusBranches[0].metric);
    System.assertEquals(1, result.sections.size());
    System.assertEquals(1, result.subjects.size());
    System.assertEquals(1, result.sectionSubjects);

    System.runAs(admin) {
      CollegeCatalogController.RecordHeader campusHeader = CollegeCatalogController.getRecordHeader(
        campus.Id
      );
      System.assertEquals('Campus', campusHeader.label);
      System.assertEquals('Yelahanka Campus', campusHeader.name);
      CollegeCatalogController.RecordHeader branchHeader = CollegeCatalogController.getRecordHeader(
        branch.Id
      );
      System.assertEquals('Branch', branchHeader.label);
      System.assertEquals(
        'Computer Science and Engineering',
        branchHeader.name
      );
      CollegeCatalogController.RecordHeader sectionHeader = CollegeCatalogController.getRecordHeader(
        section.Id
      );
      System.assertEquals('Section', sectionHeader.label);
      System.assert(sectionHeader.detail.contains('Yelahanka Campus'));
      System.assertEquals(
        'Programme',
        CollegeCatalogController.getRecordHeader(programme.Id).label
      );
      System.assertEquals(
        'Campus Branch',
        CollegeCatalogController.getRecordHeader(campusBranch.Id).label
      );
      System.assertEquals(
        'Subject',
        CollegeCatalogController.getRecordHeader(subject.Id).label
      );
      CollegeCatalogController.RecordHeader assignmentHeader = CollegeCatalogController.getRecordHeader(
        sectionSubject.Id
      );
      System.assertEquals('Section Subject', assignmentHeader.label);
      System.assertEquals('Engineering Mathematics I', assignmentHeader.name);
    }
  }

  @IsTest
  static void controllerExplainsMissingCatalogueAccess() {
    User userWithoutAccess = TestDataFactory.createUser(new List<String>());
    System.runAs(userWithoutAccess) {
      Test.startTest();
      try {
        CollegeCatalogController.getDashboard();
        System.assert(false, 'Access should be refused');
      } catch (AuraHandledException e) {
        System.assert(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
      Test.stopTest();
    }
  }

  private static Id recordTypeId(
    Schema.SObjectType objectType,
    String developerName
  ) {
    return objectType.getDescribe()
      .getRecordTypeInfosByDeveloperName()
      .get(developerName)
      .getRecordTypeId();
  }
}
