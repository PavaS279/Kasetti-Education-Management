@IsTest
private class GradingServiceTest {
  /**
   * A class taught by a teacher, three learners and three published
   * assessments (no weights):
   *   Asha   quiz 9/10  test 40/50  exam 70/100  -> 90, 80, 70
   *   Bala   quiz 5/10  test 30/50  exam absent  -> 50, 60, absent
   *   Chitra quiz 7/10  test 45/50  exam not marked
   */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      LearningCourse course = TestDataFactory.createCourse('Chemistry Honours');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-5)
      );
      CourseOffering offering = TestDataFactory.createOffering(
        course.Id,
        branch.Id,
        10
      );
      update new CourseOffering(
        Id = offering.Id,
        Name = 'Grading Class',
        Teacher_User__c = teacher.Id
      );
      List<Account> learners = new List<Account>();
      for (String name : new List<String>{ 'Asha', 'Bala', 'Chitra' }) {
        learners.add(
          PersonAccountService.buildPerson(
            name,
            'Grade' + Crypto.getRandomInteger(),
            null,
            null,
            branch.Id,
            'Learner'
          )
        );
      }
      insert learners;
      for (Account learner : learners) {
        EnrolmentService.EnrolmentRequest request = new EnrolmentService.EnrolmentRequest();
        request.learnerAccountId = learner.Id;
        request.offeringId = offering.Id;
        EnrolmentService.enrol(request);
      }
      insert new List<Course_Assessment__c>{
        assessment(offering.Id, 'Quiz 1', 'Quiz', 10, 1),
        assessment(offering.Id, 'Unit test', 'Test', 50, 2),
        assessment(offering.Id, 'Final exam', 'Exam', 100, 3)
      };
    }
    System.runAs(teacher) {
      Map<String, Course_Assessment__c> byName = assessments();
      mark(
        byName.get('Quiz 1').Id,
        new Map<String, Object>{ 'Asha' => 9, 'Bala' => 5, 'Chitra' => 7 }
      );
      mark(
        byName.get('Unit test').Id,
        new Map<String, Object>{ 'Asha' => 40, 'Bala' => 30, 'Chitra' => 45 }
      );
      mark(
        byName.get('Final exam').Id,
        new Map<String, Object>{ 'Asha' => 70, 'Bala' => 'absent' }
      );
    }
  }

  private static Course_Assessment__c assessment(
    Id offeringId,
    String name,
    String type,
    Integer maxScore,
    Integer daysAgo
  ) {
    return new Course_Assessment__c(
      Name = name,
      Course_Offering__c = offeringId,
      Assessment_Type__c = type,
      Max_Score__c = maxScore,
      Assessment_Date__c = Date.today().addDays(-daysAgo)
    );
  }

  private static void mark(Id assessmentId, Map<String, Object> marks) {
    AssessmentService.Gradebook book = AssessmentService.getGradebook(
      assessmentId
    );
    for (AssessmentService.ResultRow row : book.rows) {
      Object mark = marks.get(row.learnerName.substringBefore(' '));
      if (mark == 'absent') {
        row.absent = true;
      } else if (mark != null) {
        row.score = (Integer) mark;
      }
    }
    AssessmentService.saveResults(assessmentId, book.rows);
    AssessmentService.publish(assessmentId);
  }

  private static Map<String, Course_Assessment__c> assessments() {
    Map<String, Course_Assessment__c> result = new Map<String, Course_Assessment__c>();
    for (Course_Assessment__c a : [
      SELECT Id, Name, Course_Offering__c
      FROM Course_Assessment__c
    ]) {
      result.put(a.Name, a);
    }
    return result;
  }

  private static CourseOffering offering() {
    return [
      SELECT Id, Teacher_User__c, Grading_Status__c, Grades_Finalised_By__c
      FROM CourseOffering
      WHERE Name = 'Grading Class'
    ];
  }

  private static Map<String, CourseOfferingParticipant> enrolments() {
    Map<String, CourseOfferingParticipant> result = new Map<String, CourseOfferingParticipant>();
    for (CourseOfferingParticipant e : [
      SELECT
        Id,
        ParticipantContact.FirstName,
        Course_Score__c,
        Course_Grade__c,
        Grade_Status__c,
        Graded_Assessments__c,
        Report_Comment__c
      FROM CourseOfferingParticipant
      WHERE CourseOffering.Name = 'Grading Class'
    ]) {
      result.put(e.ParticipantContact.FirstName, e);
    }
    return result;
  }

  @IsTest
  static void publishingCalculatesProvisionalGrades() {
    Map<String, CourseOfferingParticipant> e = enrolments();
    Assert.areEqual(80, e.get('Asha').Course_Score__c, '(90 + 80 + 70) / 3');
    Assert.areEqual('A', e.get('Asha').Course_Grade__c, '80 is an A');
    Assert.areEqual(
      'Provisional',
      e.get('Asha').Grade_Status__c,
      'Provisional'
    );
    Assert.areEqual(3, e.get('Asha').Graded_Assessments__c, 'Three counted');
    Assert.areEqual(36.67, e.get('Bala').Course_Score__c, 'Absent counts as 0');
    Assert.areEqual('F', e.get('Bala').Course_Grade__c, 'Fail');
    Assert.areEqual(
      80,
      e.get('Chitra').Course_Score__c,
      'Unmarked exam left out'
    );
    Assert.areEqual(2, e.get('Chitra').Graded_Assessments__c, 'Two counted');

    AppSettings.overrides.put('Absent_Counts_As_Zero', 'false');
    System.runAs(TestDataFactory.admin()) {
      GradingService.calculate(new Set<Id>{ offering().Id });
    }
    Assert.areEqual(
      55,
      enrolments().get('Bala').Course_Score__c,
      'Absence left out'
    );
  }

  @IsTest
  static void weightsCommentsFinaliseAndReopen() {
    CourseOffering cls = offering();
    Map<String, Course_Assessment__c> byName = assessments();
    System.runAs(new User(Id = cls.Teacher_User__c)) {
      GradingController.saveWeights(
        cls.Id,
        new List<GradingService.WeightRow>{
          weight(byName.get('Quiz 1').Id, 10),
          weight(byName.get('Unit test').Id, 30),
          weight(byName.get('Final exam').Id, 60)
        }
      );
      GradingService.ClassGrades grades = GradingController.getClassGrades(
        cls.Id
      );
      Assert.isFalse(grades.equalWeights, 'Weighted');
      Assert.areEqual(3, grades.columns.size(), 'Three assessments');
      Assert.areEqual(60, grades.columns[0].share, 'Exam (oldest last): 60%');
      Assert.isTrue(grades.canEdit, 'Class teacher edits grades');
      Assert.areEqual(3, grades.rows.size(), 'Three learners');
      Assert.areEqual('Open', grades.status, 'Open');
      Assert.areEqual(
        75,
        enrolments().get('Asha').Course_Score__c,
        '9 + 24 + 42'
      );
      Assert.areEqual(
        'B',
        enrolments().get('Asha').Course_Grade__c,
        '75 is a B'
      );
      Assert.areEqual(
        85,
        enrolments().get('Chitra').Course_Score__c,
        '(700 + 2700) / 40'
      );

      GradingService.CommentRow comment = new GradingService.CommentRow();
      comment.enrolmentId = enrolments().get('Asha').Id;
      comment.comment = 'Consistent effort; revise organic reactions.';
      GradingController.saveComments(
        cls.Id,
        new List<GradingService.CommentRow>{ comment }
      );
      Assert.areEqual(
        'Consistent effort; revise organic reactions.',
        enrolments().get('Asha').Report_Comment__c,
        'Comment saved'
      );

      Test.startTest();
      Assert.areEqual(
        3,
        GradingController.finaliseGrades(cls.Id),
        'Three report cards'
      );
      Test.stopTest();
    }
    System.runAs(TestDataFactory.admin()) {
      Assert.areEqual('Final', offering().Grading_Status__c, 'Class final');
      Assert.areEqual(
        cls.Teacher_User__c,
        offering().Grades_Finalised_By__c,
        'By the teacher'
      );
      Map<String, CourseOfferingParticipant> e = enrolments();
      Assert.areEqual('Final', e.get('Asha').Grade_Status__c, 'Final');
      Id ashaId = e.get('Asha').Id;
      Assert.isNotNull(
        DocumentService.existing(ashaId, DocumentService.REPORT_CARD),
        'Report card filed'
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Message__c
          WHERE
            Event__c = 'Report_Card_Ready'
            AND Related_Record_Id__c = :ashaId
        ],
        'Family told by email and portal'
      );
      GradingService.ClassGrades finalGrades = GradingService.classGrades(
        cls.Id
      );
      Assert.areEqual('Final', finalGrades.status, 'Final');
      Assert.isNotNull(finalGrades.rows[0].reportCardId, 'Report card linked');
      Assert.isTrue(finalGrades.canReopen, 'Administrator can reopen');

      try {
        GradingService.saveComments(
          cls.Id,
          new List<GradingService.CommentRow>()
        );
        Assert.fail('Final grades are locked');
      } catch (AppException ex) {
        Assert.isTrue(ex.getMessage().contains('final'), ex.getMessage());
      }
      try {
        GradingService.reopen(cls.Id, null);
        Assert.fail('Reason needed');
      } catch (AppException ex) {
        Assert.isTrue(ex.getMessage().contains('why'), ex.getMessage());
      }

      Test.setCurrentPage(Page.KEM_Report_Card);
      ApexPages.currentPage().getParameters().put('id', ashaId);
      KemDocumentController pdf = new KemDocumentController();
      Assert.areEqual('B', pdf.reportCard.grade, 'Grade on the report card');
      Assert.areEqual(3, pdf.reportCard.lines.size(), 'Assessment lines');
      Assert.areEqual(
        '9 / 10',
        pdf.reportCard.lines[2].result,
        'Quiz line (newest first)'
      );
      Assert.isFalse(pdf.reportCard.bands.isEmpty(), 'Grade scale');

      GradingController.reopenGrades(cls.Id, 'Exam re-marked');
      Assert.areEqual('Open', offering().Grading_Status__c, 'Reopened');
      Assert.areEqual(
        'Provisional',
        enrolments().get('Asha').Grade_Status__c,
        'Provisional'
      );
      Assert.isNull(
        DocumentService.existing(ashaId, DocumentService.REPORT_CARD),
        'Old report card superseded'
      );
      try {
        GradingService.reopen(cls.Id, 'Again');
        Assert.fail('Not final');
      } catch (AppException ex) {
        Assert.isTrue(ex.getMessage().contains('not final'), ex.getMessage());
      }
      insert assessment(cls.Id, 'Retest', 'Test', 20, 0);
      try {
        GradingService.finalise(cls.Id);
        Assert.fail('Draft assessment blocks finalising');
      } catch (AppException ex) {
        Assert.isTrue(ex.getMessage().contains('Retest'), ex.getMessage());
      }
    }
  }

  @IsTest
  static void guardsAndValidation() {
    CourseOffering cls = offering();
    User other = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(other) {
      try {
        GradingService.finalise(cls.Id);
        Assert.fail('Not this teacher\'s class');
      } catch (AppException ex) {
        Assert.isNotNull(ex.getMessage(), 'Refused');
      }
    }
    System.runAs(TestDataFactory.admin()) {
      Integer failures = 0;
      for (Integer i = 0; i < 5; i++) {
        try {
          switch on i {
            when 0 {
              GradingController.saveWeights(
                cls.Id,
                new List<GradingService.WeightRow>{
                  weight(assessments().get('Quiz 1').Id, 120)
                }
              );
            }
            when 1 {
              GradingController.saveWeights(
                cls.Id,
                new List<GradingService.WeightRow>{
                  weight(TestUtil.fakeId(Course_Assessment__c.SObjectType), 10)
                }
              );
            }
            when 2 {
              GradingService.CommentRow c = new GradingService.CommentRow();
              c.enrolmentId = TestUtil.fakeId(
                CourseOfferingParticipant.SObjectType
              );
              GradingController.saveComments(
                cls.Id,
                new List<GradingService.CommentRow>{ c }
              );
            }
            when 3 {
              GradingController.getClassGrades(
                TestUtil.fakeId(CourseOffering.SObjectType)
              );
            }
            when 4 {
              GradingController.reopenGrades(cls.Id, 'Not final yet');
            }
          }
        } catch (AuraHandledException ex) {
          failures++;
        }
      }
      Assert.areEqual(5, failures, 'Every rule enforced');
      GradingService.calculate(new Set<Id>());
    }
  }

  private static GradingService.WeightRow weight(
    Id assessmentId,
    Decimal value
  ) {
    GradingService.WeightRow w = new GradingService.WeightRow();
    w.assessmentId = assessmentId;
    w.weight = value;
    return w;
  }
}
