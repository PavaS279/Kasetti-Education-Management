@IsTest
private class CollegeAcademicTest {
  @TestSetup
  static void setup() {
    CollegeTestFactory.Fixture fixture = CollegeTestFactory.create(3, 7);
    System.runAs(fixture.dean) {
      update new LearningProgram(
        Id = fixture.programme.Id,
        Terms_Per_Year__c = 1,
        Max_Backlogs_For_Promotion__c = 1
      );
      CollegeTestFactory.enrolPaid(fixture, fixture.admission);
      Campus_Branch__c nextIntake = new Campus_Branch__c(
        Campus__c = fixture.campus.Id,
        Branch__c = fixture.branch.Id,
        Academic_Year__c = '2027-28',
        Intake_Regular__c = 3,
        Intake_Lateral__c = 0,
        Admissions_Open__c = false
      );
      insert nextIntake;
      Id sectionType = Schema.SObjectType.CourseOffering.getRecordTypeInfosByDeveloperName()
        .get('College_Section')
        .getRecordTypeId();
      CourseOffering yearOne = new CourseOffering(
        Name = 'ACAD Y1 A',
        RecordTypeId = sectionType,
        LearningCourseId = fixture.branch.Id,
        Branch__c = fixture.campus.Id,
        Campus_Branch__c = fixture.intake.Id,
        Academic_Year__c = '2026-27',
        Year_Of_Study__c = 1,
        Section_Code__c = 'A',
        EnrollmentCapacity = 1,
        Class_Status__c = 'Open'
      );
      CourseOffering yearOneB = yearOne.clone();
      yearOneB.Name = 'ACAD Y1 B';
      yearOneB.Section_Code__c = 'B';
      CourseOffering yearTwo = yearOne.clone();
      yearTwo.Name = 'ACAD Y2 A';
      yearTwo.Campus_Branch__c = nextIntake.Id;
      yearTwo.Academic_Year__c = '2027-28';
      yearTwo.Year_Of_Study__c = 2;
      CourseOffering yearOneNext = yearTwo.clone();
      yearOneNext.Name = 'ACAD Y1 NEXT';
      yearOneNext.Year_Of_Study__c = 1;
      yearOneNext.Section_Code__c = 'R';
      insert new List<CourseOffering>{
        yearOne,
        yearOneB,
        yearTwo,
        yearOneNext
      };
      List<Subject__c> subjects = new List<Subject__c>{
        subject(fixture.branch.Id, 'Mathematics', 'MAT11', 1, 1),
        subject(fixture.branch.Id, 'Physics', 'PHY12', 1, 1),
        subject(fixture.branch.Id, 'Mechanics', 'MEC21', 2, 2)
      };
      insert subjects;
      insert new List<Section_Subject__c>{
        new Section_Subject__c(
          Section__c = yearOne.Id,
          Subject__c = subjects[0].Id,
          Faculty__c = fixture.dean.Id
        ),
        new Section_Subject__c(
          Section__c = yearOne.Id,
          Subject__c = subjects[1].Id,
          Faculty__c = fixture.dean.Id
        ),
        new Section_Subject__c(
          Section__c = yearTwo.Id,
          Subject__c = subjects[2].Id,
          Faculty__c = fixture.dean.Id
        )
      };
      ProgressionService.join(enrolmentId(), yearOne.Id, Date.today());
    }
  }

  private static Subject__c subject(
    Id branchId,
    String name,
    String code,
    Integer year,
    Integer term
  ) {
    return new Subject__c(
      Name = name,
      Branch__c = branchId,
      Curriculum_Version__c = '2025',
      Subject_Code__c = code,
      Year_Of_Study__c = year,
      Term__c = term,
      Credits__c = 4,
      Internal_Max__c = 50,
      Exam_Max__c = 100,
      Internal_Pass_Percent__c = 40,
      Exam_Pass_Percent__c = 35,
      Total_Pass_Percent__c = 40
    );
  }

  private static User dean() {
    return [
      SELECT Id
      FROM User
      WHERE
        Id IN (
          SELECT AssigneeId
          FROM PermissionSetAssignment
          WHERE PermissionSet.Name = 'KEM_College_Dean'
        )
      LIMIT 1
    ];
  }

  private static Id enrolmentId() {
    return [SELECT Id FROM Programme_Enrolment__c LIMIT 1].Id;
  }

  private static CourseOffering section(String name) {
    return [SELECT Id FROM CourseOffering WHERE Name = :name];
  }

  private static Section_Subject__c sectionSubject(String subjectName) {
    return [
      SELECT Id, Section__c
      FROM Section_Subject__c
      WHERE Subject__r.Name = :subjectName
    ];
  }

  private static CourseOfferingParticipant sectionEnrolment(
    String sectionName
  ) {
    return [
      SELECT
        Id,
        ParticipantContactId,
        ParticipationStatus,
        Programme_Year_Key__c,
        Year_Of_Study__c
      FROM CourseOfferingParticipant
      WHERE CourseOffering.Name = :sectionName
    ];
  }

  /** Enters and publishes one mark for the student as the subject's faculty. */
  private static Id mark(
    String subjectName,
    String component,
    Decimal max,
    Decimal score,
    Boolean absent,
    String sectionName
  ) {
    Section_Subject__c ss = sectionSubject(subjectName);
    Course_Assessment__c assessment = new Course_Assessment__c(
      Name = subjectName + ' ' + component,
      Course_Offering__c = ss.Section__c,
      Section_Subject__c = ss.Id,
      Component__c = component,
      Max_Score__c = max,
      Assessment_Type__c = 'Test',
      Assessment_Date__c = Date.today()
    );
    insert assessment;
    CourseOfferingParticipant e = sectionEnrolment(sectionName);
    AssessmentService.ResultRow row = new AssessmentService.ResultRow();
    row.learnerContactId = e.ParticipantContactId;
    row.enrolmentId = e.Id;
    row.learnerName = 'Student';
    row.score = absent ? null : score;
    row.absent = absent;
    AssessmentService.saveResults(
      assessment.Id,
      new List<AssessmentService.ResultRow>{ row }
    );
    AssessmentService.publish(assessment.Id);
    return assessment.Id;
  }

  /** Fast path for setup: a published assessment and result inserted directly, then recalculated. */
  private static Id publish(
    String subjectName,
    String component,
    Decimal max,
    Decimal score,
    String sectionName
  ) {
    Section_Subject__c ss = sectionSubject(subjectName);
    Course_Assessment__c assessment = new Course_Assessment__c(
      Name = subjectName + ' ' + component,
      Course_Offering__c = ss.Section__c,
      Section_Subject__c = ss.Id,
      Component__c = component,
      Max_Score__c = max,
      Assessment_Type__c = 'Test',
      Assessment_Date__c = Date.today(),
      Status__c = 'Published'
    );
    insert assessment;
    CourseOfferingParticipant e = sectionEnrolment(sectionName);
    insert new Assessment_Result__c(
      Course_Assessment__c = assessment.Id,
      Unique_Key__c = assessment.Id + ':' + e.ParticipantContactId,
      Learner__c = e.ParticipantContactId,
      Enrolment__c = e.Id,
      Score__c = score,
      Max_Score__c = max,
      Status__c = 'Published'
    );
    ResultService.recalculate(new Set<Id>{ ss.Id });
    return assessment.Id;
  }

  private static Subject_Result__c result(String subjectName, Integer attempt) {
    return [
      SELECT
        Id,
        Status__c,
        Result__c,
        Internal_Marks__c,
        Exam_Marks__c,
        Total_Marks__c,
        Max_Marks__c,
        Reopen_Count__c,
        Attempt__c
      FROM Subject_Result__c
      WHERE
        Section_Subject__r.Subject__r.Name = :subjectName
        AND Attempt__c = :attempt
    ];
  }

  /** Marks a subject result final directly (setup shortcut; the real path is covered by the results test). */
  private static void finalDirect(
    String subjectName,
    Integer attempt,
    Decimal internal,
    Decimal exam,
    String result
  ) {
    Subject_Result__c r = result(subjectName, attempt);
    update new Subject_Result__c(
      Id = r.Id,
      Internal_Marks__c = internal,
      Exam_Marks__c = exam,
      Total_Marks__c = internal + exam,
      Max_Marks__c = 150,
      Percentage__c = ((internal + exam) * 100 / 150).setScale(2),
      Result__c = result,
      Status__c = 'Final',
      Finalised_On__c = System.now().addHours(-1)
    );
  }

  private static void termDirect(
    String sectionName,
    Integer term,
    Integer backlogs
  ) {
    CourseOfferingParticipant e = sectionEnrolment(sectionName);
    insert new Term_Result__c(
      Unique_Key__c = ResultService.termKey(e.Id, term),
      Section_Enrolment__c = e.Id,
      Programme_Enrolment__c = enrolmentId(),
      Term__c = term,
      Status__c = 'Final',
      Outcome__c = backlogs == 0 ? 'Pass' : 'Pass with backlog',
      Backlogs__c = backlogs
    );
  }

  /** Year 1 final: Mathematics passed, Physics failed (one backlog). */
  private static void yearOneFinalDirect() {
    finalDirect('Mathematics', 1, 40, 80, 'Pass');
    finalDirect('Physics', 1, 30, 20, 'Fail');
    termDirect('ACAD Y1 A', 1, 1);
  }

  @IsTest
  static void joiningCreatesDraftResultsAndIsIdempotent() {
    System.runAs(dean()) {
      CourseOfferingParticipant e = sectionEnrolment('ACAD Y1 A');
      Datetime start = System.now().addDays(-1);
      Class_Session__c period = new Class_Session__c(
        Name = 'Maths period',
        Course_Offering__c = section('ACAD Y1 A').Id,
        Section_Subject__c = sectionSubject('Mathematics').Id,
        Teacher_User__c = UserInfo.getUserId(),
        Start__c = start,
        End__c = start.addHours(1)
      );
      insert period;
      insert new Session_Attendance__c(
        Class_Session__c = period.Id,
        Learner__c = e.ParticipantContactId,
        Enrolment__c = e.Id,
        Status__c = 'Present',
        Unique_Key__c = period.Id + ':' + e.ParticipantContactId
      );
      Test.startTest();
      System.assertEquals(
        e.Id,
        ProgressionService.join(
          enrolmentId(),
          section('ACAD Y1 A').Id,
          Date.today()
        )
      );
      try {
        ProgressionService.join(
          enrolmentId(),
          section('ACAD Y1 B').Id,
          Date.today()
        );
        System.assert(false, 'One section per academic year');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('another section'));
      }
      try {
        CollegeAcademicController.joinSection(
          enrolmentId(),
          section('ACAD Y2 A').Id,
          Date.today()
        );
        System.assert(false, 'Wrong year of study');
      } catch (AuraHandledException expected) {
        System.assert(true);
      }
      CollegeAcademicController.EnrolmentPanel panel = CollegeAcademicController.getEnrolmentPanel(
        enrolmentId()
      );
      Test.stopTest();
      System.assertEquals(1, e.Year_Of_Study__c);
      System.assertEquals(enrolmentId() + '|2026-27', e.Programme_Year_Key__c);
      System.assertEquals(
        2,
        [
          SELECT COUNT()
          FROM Subject_Result__c
          WHERE Section_Enrolment__c = :e.Id AND Status__c = 'Draft'
        ]
      );
      System.assertEquals(
        Date.today(),
        [SELECT Joining_Date__c FROM Programme_Enrolment__c].Joining_Date__c
      );
      System.assertEquals('ACAD Y1 A', panel.currentSection);
      System.assertEquals(2, panel.subjects.size());
      Decimal mathsAttendance;
      for (CollegeAcademicController.SubjectRow row : panel.subjects) {
        if (row.subject == 'Mathematics') {
          mathsAttendance = row.attendancePercent;
        }
      }
      System.assertEquals(100, mathsAttendance);
      System.assert(panel.canAct);
    }
  }

  @IsTest
  static void resultsCalculateFinaliseLockAndReopen() {
    System.runAs(dean()) {
      Test.startTest();
      publish('Mathematics', 'Internal', 50, 40, 'ACAD Y1 A');
      try {
        ResultService.finalise(sectionSubject('Mathematics').Id);
        System.assert(false, 'Exam marks are required before finalising');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('exam marks'));
      }
      mark('Mathematics', 'Exam', 100, 80, false, 'ACAD Y1 A');

      System.assertEquals(
        1,
        CollegeAcademicController.finaliseResults(
          sectionSubject('Mathematics').Id
        )
      );
      Subject_Result__c maths = result('Mathematics', 1);
      System.assertEquals('Final', maths.Status__c);
      System.assertEquals('Pass', maths.Result__c);
      System.assertEquals(40, maths.Internal_Marks__c);
      System.assertEquals(80, maths.Exam_Marks__c);
      System.assertEquals(150, maths.Max_Marks__c);
      System.assertEquals(
        0,
        [SELECT COUNT() FROM Term_Result__c],
        'Physics is still open'
      );
      try {
        update new Subject_Result__c(Id = maths.Id, Exam_Marks__c = 100);
        System.assert(false, 'Final results are locked');
      } catch (DmlException expected) {
        System.assert(expected.getMessage().contains('locked'));
      }
      try {
        mark('Mathematics', 'Exam', 100, 99, false, 'ACAD Y1 A');
        System.assert(false, 'No new marks on a final subject');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('final'));
      }
      publish('Physics', 'Internal', 50, 30, 'ACAD Y1 A');
      publish('Physics', 'Exam', 100, 20, 'ACAD Y1 A');
      ResultService.finalise(sectionSubject('Physics').Id);
      Term_Result__c term = [
        SELECT
          Status__c,
          Outcome__c,
          Backlogs__c,
          Subjects_Passed__c,
          Percentage__c
        FROM Term_Result__c
      ];
      System.assertEquals('Final', term.Status__c);
      System.assertEquals('Pass with backlog', term.Outcome__c);
      System.assertEquals(1, term.Backlogs__c);
      System.assertEquals('Fail', result('Physics', 1).Result__c);
      System.assert(
        [
          SELECT COUNT()
          FROM Message__c
          WHERE Event__c = 'College_Results_Published'
        ] > 0
      );
      try {
        delete new Subject_Result__c(Id = maths.Id);
        System.assert(false, 'Final results cannot be deleted');
      } catch (DmlException expected) {
        System.assert(expected.getMessage().contains('cannot be deleted'));
      }
      MessageService.disabled = true;

      CollegeAcademicController.reopenResults(
        new List<Id>{ maths.Id },
        'Recount requested'
      );
      Test.stopTest();
      maths = result('Mathematics', 1);
      System.assertEquals('Reopened', maths.Status__c);
      System.assertEquals(1, maths.Reopen_Count__c);
      System.assertEquals(
        'Reopened',
        [SELECT Status__c FROM Term_Result__c].Status__c
      );
      System.assertEquals(
        'Planned',
        [
          SELECT Status__c
          FROM Section_Subject__c
          WHERE Id = :sectionSubject('Mathematics').Id
        ]
        .Status__c
      );
    }
  }

  @IsTest
  static void reopenedResultsCanBeFinalisedAgain() {
    System.runAs(dean()) {
      Test.startTest();
      MessageService.disabled = true;
      publish('Mathematics', 'Internal', 50, 40, 'ACAD Y1 A');
      publish('Mathematics', 'Exam', 100, 80, 'ACAD Y1 A');
      finalDirect('Mathematics', 1, 40, 80, 'Pass');
      finalDirect('Physics', 1, 30, 70, 'Pass');
      termDirect('ACAD Y1 A', 1, 0);
      ResultService.finalise(sectionSubject('Physics').Id);
      CollegeAcademicController.reopenResults(
        new List<Id>{ result('Mathematics', 1).Id },
        'Recount requested'
      );
      System.assertEquals(
        'Reopened',
        [SELECT Status__c FROM Term_Result__c].Status__c
      );
      ResultService.finalise(sectionSubject('Mathematics').Id);
      System.assertEquals(
        'Final',
        [SELECT Status__c FROM Term_Result__c].Status__c
      );
      CollegeAcademicController.SectionPanel panel = CollegeAcademicController.getSectionPanel(
        section('ACAD Y1 A').Id
      );
      System.assertEquals(2, panel.subjects.size());
      System.assert(panel.canFinalise && panel.canReopen);
      Test.stopTest();
    }
  }

  @IsTest
  static void collegeSectionsAreNeverGradedAsOneClass() {
    System.runAs(dean()) {
      Id sectionId = section('ACAD Y1 A').Id;
      Test.startTest();
      GradingService.calculate(new Set<Id>{ sectionId });
      try {
        GradingService.finalise(sectionId);
        System.assert(false, 'College sections finalise by subject');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('section subject'));
      }
      Test.stopTest();
      System.assertEquals(
        null,
        [SELECT Course_Grade__c FROM CourseOfferingParticipant LIMIT 1]
        .Course_Grade__c
      );
    }
  }

  @IsTest
  static void promotionCarriesBacklogAndBillsTheNextYear() {
    System.runAs(dean()) {
      yearOneFinalDirect();
      Id enrolmentId = enrolmentId();
      Id yearTwo = section('ACAD Y2 A').Id;
      Test.startTest();
      Id next = CollegeAcademicController.promote(enrolmentId, yearTwo);
      System.assertEquals(
        next,
        ProgressionService.promote(enrolmentId, yearTwo),
        'Promotion is idempotent'
      );
      try {
        ProgressionService.completeProgramme(enrolmentId);
        System.assert(false, 'Year 2 results are not final yet');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('Finalise'));
      }
      Test.stopTest();
      System.assertEquals(
        2,
        [SELECT Current_Year_Of_Study__c FROM Programme_Enrolment__c]
        .Current_Year_Of_Study__c
      );
      System.assertEquals(
        'Completed',
        sectionEnrolment('ACAD Y1 A').ParticipationStatus
      );
      System.assertEquals(2, sectionEnrolment('ACAD Y2 A').Year_Of_Study__c);
      Subject_Result__c retake = result('Physics', 2);
      System.assertEquals('Draft', retake.Status__c);
      System.assertEquals(
        30,
        retake.Internal_Marks__c,
        'Internal marks carry over'
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Student_Invoice__c
          WHERE Programme_Enrolment__c = :enrolmentId AND Year_Of_Study__c = 2
        ]
      );
      System.assertEquals(
        1,
        [
          SELECT COUNT()
          FROM Subject_Result__c
          WHERE Section_Subject__r.Subject__r.Name = 'Mechanics'
        ]
      );
    }
  }

  @IsTest
  static void completionRecordsTheQualificationOnce() {
    System.runAs(dean()) {
      MessageService.disabled = true;
      yearOneFinalDirect();
      Id enrolmentId = enrolmentId();
      // A one-year programme: completion follows year 1 once the backlog is cleared.
      update new LearningProgram(
        Id = [SELECT Programme__c FROM Programme_Enrolment__c]
        .Programme__c,
        Duration_Years__c = 1
      );
      Test.startTest();
      try {
        ProgressionService.completeProgramme(enrolmentId);
        System.assert(false, 'Backlogs block completion');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('backlogs'));
      }
      ResultService.registerReattempt(
        result('Physics', 1).Id,
        sectionEnrolment('ACAD Y1 A').Id
      );
      // Re-exam after the first attempt was finalised; internal marks carry over.
      publish('Physics', 'Exam', 100, 70, 'ACAD Y1 A');
      ResultService.finalise(sectionSubject('Physics').Id);
      Subject_Result__c retake = result('Physics', 2);
      System.assertEquals('Pass', retake.Result__c);
      System.assertEquals(30, retake.Internal_Marks__c);
      Id qualificationId = CollegeAcademicController.completeProgramme(
        enrolmentId
      );
      System.assertEquals(
        qualificationId,
        ProgressionService.completeProgramme(enrolmentId),
        'Completion is idempotent'
      );
      Test.stopTest();
      System.assertEquals(
        'Completed',
        [SELECT Status__c FROM Programme_Enrolment__c].Status__c
      );
      Academic_Qualification__c q = [
        SELECT
          Level__c,
          Verified__c,
          Percentage__c,
          Source_Programme_Enrolment__c
        FROM Academic_Qualification__c
        WHERE Id = :qualificationId
      ];
      System.assertEquals('BE', q.Level__c);
      System.assert(q.Verified__c);
      System.assertEquals(enrolmentId, q.Source_Programme_Enrolment__c);
      System.assert(q.Percentage__c > 0 && q.Percentage__c <= 100);
      System.assertEquals(0, ResultService.openBacklogs(enrolmentId).size());
    }
  }

  @IsTest
  static void repeatingTheYearUsesANextYearSection() {
    System.runAs(dean()) {
      yearOneFinalDirect();
      Id enrolmentId = enrolmentId();
      Id repeatSection = section('ACAD Y1 NEXT').Id;
      Test.startTest();
      try {
        ProgressionService.repeatYear(enrolmentId, repeatSection, ' ');
        System.assert(false, 'Reason required');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('reason'));
      }
      Id repeated = CollegeAcademicController.repeatYear(
        enrolmentId,
        repeatSection,
        'Attendance shortage'
      );
      System.assertEquals(
        repeated,
        ProgressionService.repeatYear(enrolmentId, repeatSection, 'Again')
      );
      Test.stopTest();
      Programme_Enrolment__c e = [
        SELECT Current_Year_Of_Study__c, Status_Reason__c
        FROM Programme_Enrolment__c
      ];
      System.assertEquals(1, e.Current_Year_Of_Study__c);
      System.assert(e.Status_Reason__c.startsWith('Repeating year 1'));
      System.assertEquals(
        'Completed',
        sectionEnrolment('ACAD Y1 A').ParticipationStatus
      );
      System.assertEquals(1, sectionEnrolment('ACAD Y1 NEXT').Year_Of_Study__c);
    }
  }

  @IsTest
  static void deanDiscontinuesAndOthersCannot() {
    Id enrolmentId = enrolmentId();
    User finance = TestDataFactory.createUser(
      new List<String>{ 'KEM_Finance' }
    );
    System.runAs(finance) {
      try {
        ProgressionService.discontinue(enrolmentId, 'Left');
        System.assert(false, 'Dean permission required');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('permission'));
      }
      try {
        ResultService.finalise(sectionSubject('Mathematics').Id);
        System.assert(false, 'Finalise permission required');
      } catch (AppException expected) {
        System.assert(expected.getMessage().contains('permission'));
      }
    }
    System.runAs(finance) {
      Integer refused = 0;
      List<Id> none = new List<Id>();
      try {
        CollegeAcademicController.finaliseResults(
          sectionSubject('Mathematics').Id
        );
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.reopenResults(none, 'x');
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.promote(enrolmentId, section('ACAD Y2 A').Id);
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.repeatYear(
          enrolmentId,
          section('ACAD Y1 NEXT').Id,
          'x'
        );
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.completeProgramme(enrolmentId);
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.getSectionPanel(null);
      } catch (AuraHandledException expected) {
        refused++;
      }
      try {
        CollegeAcademicController.getEnrolmentPanel(null);
      } catch (AuraHandledException expected) {
        refused++;
      }
      System.assertEquals(
        7,
        refused,
        'Every Dean action is refused without permission'
      );
    }
    System.runAs(dean()) {
      Test.startTest();
      CollegeAcademicController.discontinue(
        enrolmentId,
        'Moved to another city'
      );
      ProgressionService.discontinue(enrolmentId, 'Again');
      Test.stopTest();
      Programme_Enrolment__c e = [
        SELECT Status__c, Roll_Number__c, Status_Reason__c
        FROM Programme_Enrolment__c
      ];
      System.assertEquals('Discontinued', e.Status__c);
      System.assertEquals('Moved to another city', e.Status_Reason__c);
      System.assertNotEquals(null, e.Roll_Number__c, 'The roll number is kept');
      System.assertEquals(
        'Withdrew',
        sectionEnrolment('ACAD Y1 A').ParticipationStatus
      );
    }
  }
}
