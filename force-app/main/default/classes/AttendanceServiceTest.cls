@IsTest
private class AttendanceServiceTest {
  private class Fixture {
    Branch__c branch;
    CourseOffering offering;
    User teacher;
    List<Account> learners = new List<Account>();
    Class_Session__c session;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch(); // attendance threshold 80%
    f.teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    LearningCourse course = TestDataFactory.createCourse('Chemistry');
    insert new Fee_Price__c(
      Learning_Course__c = course.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Term',
      Amount__c = 100,
      Effective_From__c = Date.today().addDays(-30)
    );
    f.offering = TestDataFactory.createOffering(course.Id, f.branch.Id, 10);
    update new CourseOffering(
      Id = f.offering.Id,
      Teacher_User__c = f.teacher.Id
    );
    for (Integer i = 0; i < 3; i++) {
      f.learners.add(
        PersonAccountService.buildPerson(
          'A' + i,
          'Attend' + i + Crypto.getRandomInteger(),
          null,
          null,
          f.branch.Id,
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
    Datetime start = System.now().addHours(-2);
    f.session = new Class_Session__c(
      Name = 'Past session',
      Course_Offering__c = f.offering.Id,
      Teacher_User__c = f.teacher.Id,
      Start__c = start,
      End__c = start.addHours(1)
    );
    insert f.session;
    return f;
  }

  private static List<AttendanceService.RegisterRow> mark(
    AttendanceService.Register register,
    List<String> statuses
  ) {
    for (Integer i = 0; i < register.rows.size(); i++) {
      register.rows[i].status = statuses[i];
      register.rows[i].minutesLate = statuses[i] == 'Late' ? 10 : null;
    }
    return register.rows;
  }

  @IsTest
  static void teacherMarksRegisterAndStatisticsUpdate() {
    Fixture f;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
    }
    System.runAs(f.teacher) {
      AttendanceService.Register register = AttendanceController.getRegister(
        f.session.Id
      );
      Assert.isTrue(register.canMark, 'Session teacher can mark');
      Assert.areEqual(3, register.rows.size(), 'All enrolled learners listed');
      AttendanceController.saveRegister(
        f.session.Id,
        mark(register, new List<String>{ 'Present', 'Late', 'Absent' }),
        'Present'
      );
    }
    System.runAs(TestDataFactory.admin()) {
      Class_Session__c session = [
        SELECT Status__c, Attendance_Marked__c, Teacher_Attendance__c
        FROM Class_Session__c
        WHERE Id = :f.session.Id
      ];
      Assert.areEqual('Completed', session.Status__c, 'Session completed');
      Assert.isTrue(session.Attendance_Marked__c, 'Marked');
      Assert.areEqual(
        'Present',
        session.Teacher_Attendance__c,
        'Teacher attendance'
      );
      Assert.areEqual(
        3,
        [
          SELECT COUNT()
          FROM Session_Attendance__c
          WHERE Class_Session__c = :f.session.Id
        ],
        'Three marks'
      );
      Assert.areEqual(
        10,
        [
          SELECT Minutes_Late__c
          FROM Session_Attendance__c
          WHERE Status__c = 'Late'
        ]
        .Minutes_Late__c,
        'Minutes late kept'
      );
      CourseOfferingParticipant absent = [
        SELECT
          Attendance_Rate__c,
          Sessions_Missed__c,
          Below_Attendance_Threshold__c,
          ParticipantContactId
        FROM CourseOfferingParticipant
        WHERE Sessions_Missed__c = 1
      ];
      Assert.areEqual(0, absent.Attendance_Rate__c, '0% attendance');
      Assert.isTrue(
        absent.Below_Attendance_Threshold__c,
        'Flagged below threshold'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Task
          WHERE
            WhoId = :absent.ParticipantContactId
            AND Subject LIKE 'Attendance below threshold%'
        ],
        'Follow-up task created'
      );
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM CourseOfferingParticipant
          WHERE Attendance_Rate__c = 100
        ],
        'Present and late count as attended'
      );
    }
  }

  @IsTest
  static void correctionsAreAuditedAndRecalculated() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      AttendanceService.saveRegister(
        f.session.Id,
        mark(
          AttendanceService.getRegister(f.session.Id),
          new List<String>{ 'Present', 'Present', 'Absent' }
        ),
        'Present'
      );
      AttendanceService.Register register = AttendanceService.getRegister(
        f.session.Id
      );
      Assert.isTrue(register.alreadyMarked, 'Register shows it was marked');
      AttendanceService.saveRegister(
        f.session.Id,
        mark(register, new List<String>{ 'Present', 'Present', 'Excused' }),
        'Present'
      );
      Session_Attendance__c corrected = [
        SELECT Corrected__c, Previous_Status__c, Enrolment__c
        FROM Session_Attendance__c
        WHERE Status__c = 'Excused'
      ];
      Assert.isTrue(corrected.Corrected__c, 'Correction flagged');
      Assert.areEqual(
        'Absent',
        corrected.Previous_Status__c,
        'Previous status kept'
      );
      CourseOfferingParticipant enrolment = [
        SELECT Attendance_Rate__c, Below_Attendance_Threshold__c
        FROM CourseOfferingParticipant
        WHERE Id = :corrected.Enrolment__c
      ];
      Assert.isNull(
        enrolment.Attendance_Rate__c,
        'Excused sessions do not count against the learner'
      );
      Assert.isFalse(enrolment.Below_Attendance_Threshold__c, 'Flag cleared');
      Assert.areEqual(
        3,
        [SELECT COUNT() FROM Session_Attendance__c],
        'Upsert keeps one mark per learner'
      );
    }
  }

  @IsTest
  static void guardsWhoAndWhenAttendanceIsTaken() {
    Fixture f;
    User otherTeacher;
    System.runAs(TestDataFactory.admin()) {
      f = fixture();
      otherTeacher = TestDataFactory.createUserWithLicense(
        TestDataFactory.persona('KEM_Teacher')
      );
    }
    System.runAs(otherTeacher) {
      AttendanceService.Register register = AttendanceService.getRegister(
        f.session.Id
      );
      Assert.isFalse(register.canMark, 'Another teacher cannot mark');
      try {
        AttendanceController.saveRegister(
          f.session.Id,
          mark(register, new List<String>{ 'Present', 'Present', 'Present' }),
          null
        );
        Assert.fail('Other teacher must be refused');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Only the session teacher'),
          e.getMessage()
        );
      }
    }
    System.runAs(TestDataFactory.admin()) {
      Datetime future = System.now().addDays(2);
      Class_Session__c later = new Class_Session__c(
        Name = 'Future',
        Course_Offering__c = f.offering.Id,
        Start__c = future,
        End__c = future.addHours(1)
      );
      insert later;
      expectFailure(
        later.Id,
        new List<String>{ 'Present', 'Present', 'Present' },
        'one hour before'
      );
      expectFailure(
        f.session.Id,
        new List<String>{ null, null, null },
        'at least one'
      );
      expectFailure(
        f.session.Id,
        new List<String>{ 'Sleeping', null, null },
        'Unknown attendance status'
      );
      update new Class_Session__c(
        Id = f.session.Id,
        Status__c = 'Cancelled',
        Cancellation_Reason__c = 'Flood'
      );
      expectFailure(
        f.session.Id,
        new List<String>{ 'Present', 'Present', 'Present' },
        'cancelled'
      );
    }
  }

  @IsTest
  static void registerOnlyListsLearnersActiveOnTheSessionDate() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      CourseOfferingParticipant leaver = [
        SELECT Id
        FROM CourseOfferingParticipant
        WHERE ParticipantAccountId = :f.learners[0].Id
      ];
      EnrolmentService.withdraw(leaver.Id, 'Moved', null);
      update new CourseOfferingParticipant(
        Id = leaver.Id,
        EndDate = Date.today().addDays(-10)
      );
      Assert.areEqual(
        2,
        AttendanceService.getRegister(f.session.Id).rows.size(),
        'Withdrawn learner not on the register'
      );
      User coordinator = TestDataFactory.createUserWithLicense(
        TestDataFactory.persona('KEM_Academic_Coordinator')
      );
      System.runAs(coordinator) {
        Assert.isTrue(
          AttendanceService.getRegister(f.session.Id).canMark,
          'Academic coordinator can mark any session'
        );
      }
    }
  }

  private static void expectFailure(
    Id sessionId,
    List<String> statuses,
    String expected
  ) {
    try {
      AttendanceService.saveRegister(
        sessionId,
        mark(AttendanceService.getRegister(sessionId), statuses),
        null
      );
      Assert.fail('Expected: ' + expected);
    } catch (AppException e) {
      Assert.isTrue(
        e.getMessage().contains(expected),
        expected + ' → ' + e.getMessage()
      );
    }
  }
}
