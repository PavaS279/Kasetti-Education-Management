@IsTest
private class AssessmentServiceTest {
  private class Fixture {
    CourseOffering offering;
    User teacher;
    List<Account> learners = new List<Account>();
    Course_Assessment__c assessment;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    Branch__c branch = TestDataFactory.createBranch();
    f.teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    LearningCourse course = TestDataFactory.createCourse('History');
    insert new Fee_Price__c(
      Learning_Course__c = course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = 100,
      Effective_From__c = Date.today().addDays(-5)
    );
    f.offering = TestDataFactory.createOffering(course.Id, branch.Id, 10);
    update new CourseOffering(
      Id = f.offering.Id,
      Teacher_User__c = f.teacher.Id
    );
    for (Integer i = 0; i < 3; i++) {
      f.learners.add(
        PersonAccountService.buildPerson(
          'G' + i,
          'Grade' + i + Crypto.getRandomInteger(),
          null,
          null,
          branch.Id,
          'Learner'
        )
      );
    }
    insert f.learners;
    for (Account learner : f.learners) {
      EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
      r.learnerAccountId = learner.Id;
      r.offeringId = f.offering.Id;
      EnrolmentService.enrol(r);
    }
    f.assessment = new Course_Assessment__c(
      Name = 'Unit test 1',
      Course_Offering__c = f.offering.Id,
      Max_Score__c = 50,
      Assessment_Type__c = 'Test',
      Assessment_Date__c = Date.today()
    );
    insert f.assessment;
    return f;
  }

  private static List<AssessmentService.ResultRow> score(
    AssessmentService.Gradebook book,
    List<Decimal> scores
  ) {
    for (Integer i = 0; i < book.rows.size(); i++) {
      book.rows[i].score = scores[i];
      book.rows[i].absent = scores[i] == null;
      book.rows[i].feedback = 'Feedback ' + i;
    }
    return book.rows;
  }

  @IsTest
  static void teacherEntersAndPublishesResults() {
    Fixture f;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
    }
    System.runAs(f.teacher) {
      AssessmentService.Gradebook book = AssessmentController.getGradebook(
        f.assessment.Id
      );
      Assert.isTrue(book.canEdit, 'Class teacher can enter results');
      Assert.areEqual(3, book.rows.size(), 'All enrolled learners');
      Assert.areEqual(6, book.bands.size(), 'Standard scale');
      AssessmentController.saveResults(
        f.assessment.Id,
        score(book, new List<Decimal>{ 46, 31, null })
      );
      AssessmentController.saveResults(
        f.assessment.Id,
        score(
          AssessmentService.getGradebook(f.assessment.Id),
          new List<Decimal>{ 47, 31, null }
        )
      );
      AssessmentController.publish(f.assessment.Id);
      try {
        AssessmentController.saveResults(
          f.assessment.Id,
          score(
            AssessmentService.getGradebook(f.assessment.Id),
            new List<Decimal>{ 10, 10, 10 }
          )
        );
        Assert.fail('Published results are locked');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('locked'), e.getMessage());
      }
    }
    System.runAs(TestDataFactory.admin()) {
      Map<Integer, String> gradeByScore = new Map<Integer, String>();
      for (Assessment_Result__c r : [
        SELECT Score__c, Grade__c, Status__c, Percentage__c
        FROM Assessment_Result__c
      ]) {
        gradeByScore.put(
          r.Score__c == null ? null : r.Score__c.intValue(),
          r.Grade__c
        );
        Assert.areEqual('Published', r.Status__c, 'Published');
      }
      Assert.areEqual(
        3,
        gradeByScore.size(),
        'One result per learner (upsert)'
      );
      Assert.areEqual('A+', gradeByScore.get(47), '94% is A+');
      Assert.areEqual('C', gradeByScore.get(31), '62% is C');
      Assert.areEqual('ABS', gradeByScore.get(null), 'Absent');
      Course_Assessment__c published = [
        SELECT Status__c, Average_Percentage__c, Published_By__c
        FROM Course_Assessment__c
        WHERE Id = :f.assessment.Id
      ];
      Assert.areEqual('Published', published.Status__c, 'Assessment published');
      Assert.areEqual(
        78,
        published.Average_Percentage__c,
        'Average of graded results'
      );
      Assert.areEqual(
        f.teacher.Id,
        published.Published_By__c,
        'Publisher stamped'
      );
      Assert.areEqual(
        1,
        AssessmentController.getLearnerResults(f.learners[0].Id).size(),
        'Learner sees published result'
      );
      Assert.areEqual(
        1,
        AssessmentController.getClassAssessments(f.offering.Id).size(),
        'Class assessments listed'
      );
    }
  }

  @IsTest
  static void validatesScoresAndAccess() {
    Fixture f;
    User otherTeacher;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
      otherTeacher = TestDataFactory.createUserWithLicense(
        TestDataFactory.persona('KEM_Teacher')
      );
      try {
        AssessmentService.saveResults(
          f.assessment.Id,
          score(
            AssessmentService.getGradebook(f.assessment.Id),
            new List<Decimal>{ 51, 1, 1 }
          )
        );
        Assert.fail('Score above maximum');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('between 0 and 50'),
          e.getMessage()
        );
      }
      try {
        AssessmentService.publish(f.assessment.Id);
        Assert.fail('Nothing to publish');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('before publishing'),
          e.getMessage()
        );
      }
      AssessmentService.Gradebook empty = AssessmentService.getGradebook(
        f.assessment.Id
      );
      for (AssessmentService.ResultRow row : empty.rows) {
        row.absent = false;
      }
      try {
        AssessmentService.saveResults(f.assessment.Id, empty.rows);
        Assert.fail('Nothing entered');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('at least one'), e.getMessage());
      }
      Assert.areEqual(
        'F',
        AssessmentService.gradeFor(10, AssessmentService.bands(null)),
        'Lowest band'
      );
      try {
        AssessmentService.bands('Nope');
        Assert.fail('Unknown scale');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('no grade bands'),
          e.getMessage()
        );
      }
    }
    System.runAs(otherTeacher) {
      Assert.isFalse(
        AssessmentService.getGradebook(f.assessment.Id).canEdit,
        'Other teacher cannot edit'
      );
      try {
        AssessmentController.publish(f.assessment.Id);
        Assert.fail('Other teacher must be refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Only the class teacher'),
          e.getMessage()
        );
      }
    }
  }
}
