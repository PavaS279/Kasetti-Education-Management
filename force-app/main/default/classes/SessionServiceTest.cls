@IsTest
private class SessionServiceTest {
  private class Fixture {
    Branch__c branch;
    CourseOffering offering;
    Room__c room;
    User teacher;
  }

  private static Fixture fixture() {
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    f.room = TestDataFactory.createRoom(f.branch.Id, 30);
    f.teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    LearningCourse course = TestDataFactory.createCourse('Geometry');
    f.offering = TestDataFactory.createOffering(course.Id, f.branch.Id, 10);
    update new CourseOffering(
      Id = f.offering.Id,
      Room__c = f.room.Id,
      Teacher_User__c = f.teacher.Id
    );
    return f;
  }

  private static CourseOfferingSchedule pattern(
    Id offeringId,
    Date fromDate,
    Date toDate
  ) {
    CourseOfferingSchedule p = new CourseOfferingSchedule(
      CourseOfferingId = offeringId,
      Description = 'Mon & Wed 10:00',
      IsMonday = true,
      IsWednesday = true,
      StartTime = Time.newInstance(10, 0, 0, 0),
      EndTime = Time.newInstance(11, 30, 0, 0),
      StartDate = fromDate
    );
    // CourseOfferingSchedule.EndDate is not grantable to the persona in this org;
    // generation falls back to the class end date, so set that instead.
    update new CourseOffering(
      Id = offeringId,
      EndDate = Datetime.newInstance(toDate, Time.newInstance(23, 0, 0, 0))
    );
    insert p;
    return p;
  }

  private static Date nextMonday() {
    Date d = Date.today().addDays(1);
    while (
      !SessionService.runsOn(new CourseOfferingSchedule(IsMonday = true), d)
    ) {
      d = d.addDays(1);
    }
    return d;
  }

  @IsTest
  static void generatesSessionsIdempotentlyAndSkipsClosures() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Date monday = nextMonday();
      pattern(f.offering.Id, monday, monday.addDays(13)); // 2 weeks → 4 sessions
      insert new Calendar_Closure__c(
        Name = 'Holiday',
        Start_Date__c = monday.addDays(2),
        End_Date__c = monday.addDays(2)
      );
      SessionService.GenerationResult first = TimetableController.generateSessions(
        f.offering.Id
      );
      Assert.areEqual(
        3,
        first.created,
        'Two weeks of Mon/Wed minus one closure ' + first.conflicts
      );
      Assert.areEqual(1, first.skippedClosures, 'Closure skipped');
      SessionService.GenerationResult second = TimetableController.generateSessions(
        f.offering.Id
      );
      Assert.areEqual(0, second.created, 'Regeneration creates nothing new');
      Assert.areEqual(
        3,
        second.skippedExisting,
        'Existing sessions recognised'
      );
      Class_Session__c s = [
        SELECT
          Room__c,
          Teacher_User__c,
          Branch__c,
          Duration_Minutes__c,
          Status__c
        FROM Class_Session__c
        LIMIT 1
      ];
      Assert.areEqual(f.room.Id, s.Room__c, 'Default room applied');
      Assert.areEqual(f.teacher.Id, s.Teacher_User__c, 'Teacher applied');
      Assert.areEqual(90, s.Duration_Minutes__c, 'Duration formula');
      Assert.areEqual('Scheduled', s.Status__c, 'Scheduled');
    }
  }

  @IsTest
  static void rejectsTeacherAndRoomDoubleBooking() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Datetime start = Datetime.newInstance(
        nextMonday(),
        Time.newInstance(10, 0, 0, 0)
      );
      TimetableController.addSession(
        f.offering.Id,
        start,
        start.addMinutes(90),
        'Extra',
        null
      );
      LearningCourse other = TestDataFactory.createCourse('Art');
      CourseOffering otherClass = TestDataFactory.createOffering(
        other.Id,
        f.branch.Id,
        10
      );
      update new CourseOffering(
        Id = otherClass.Id,
        Teacher_User__c = f.teacher.Id
      );
      try {
        TimetableController.addSession(
          otherClass.Id,
          start.addMinutes(30),
          start.addMinutes(120),
          'Extra',
          null
        );
        Assert.fail('Teacher double-booking must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('teacher'), e.getMessage());
      }
      update new CourseOffering(Id = otherClass.Id, Teacher_User__c = null);
      try {
        TimetableController.addSession(
          otherClass.Id,
          start,
          start.addMinutes(60),
          'Extra',
          f.room.Id
        );
        Assert.fail('Room double-booking must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('room'), e.getMessage());
      }
      Id adjacent = TimetableController.addSession(
        otherClass.Id,
        start.addMinutes(90),
        start.addMinutes(150),
        'Extra',
        f.room.Id
      );
      Assert.isNotNull(adjacent, 'Back-to-back bookings are allowed');

      List<Class_Session__c> batch = new List<Class_Session__c>{
        new Class_Session__c(
          Name = 'A',
          Course_Offering__c = otherClass.Id,
          Room__c = f.room.Id,
          Start__c = start.addDays(1),
          End__c = start.addDays(1).addHours(1)
        ),
        new Class_Session__c(
          Name = 'B',
          Course_Offering__c = otherClass.Id,
          Room__c = f.room.Id,
          Start__c = start.addDays(1),
          End__c = start.addDays(1).addHours(1)
        )
      };
      List<Database.SaveResult> results = Database.insert(batch, false);
      Assert.isTrue(
        results[0].isSuccess() && !results[1].isSuccess(),
        'Clash within one batch rejected'
      );
    }
  }

  @IsTest
  static void reschedulesCancelsAndPreviewsMoves() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Datetime start = Datetime.newInstance(
        nextMonday(),
        Time.newInstance(10, 0, 0, 0)
      );
      Id sessionId = TimetableController.addSession(
        f.offering.Id,
        start,
        start.addMinutes(60),
        'Extra',
        null
      );
      Id blockerId = TimetableController.addSession(
        f.offering.Id,
        start.addHours(3),
        start.addHours(4),
        'Extra',
        null
      );

      TimetableController.MovePreview clash = TimetableController.previewMove(
        sessionId,
        start.addHours(3),
        start.addHours(4),
        null
      );
      Assert.isTrue(
        clash.blocked,
        'Moving onto another session of the same teacher is blocked'
      );
      TimetableController.MovePreview clear = TimetableController.previewMove(
        sessionId,
        start.addHours(1),
        start.addHours(2),
        null
      );
      Assert.isFalse(clear.blocked, 'Free slot is not blocked');

      TimetableController.reschedule(
        sessionId,
        start.addHours(1),
        start.addHours(2),
        null,
        'Teacher request'
      );
      Class_Session__c moved = [
        SELECT Start__c, Original_Start__c, Rescheduled__c
        FROM Class_Session__c
        WHERE Id = :sessionId
      ];
      Assert.areEqual(start.addHours(1), moved.Start__c, 'Moved');
      Assert.areEqual(start, moved.Original_Start__c, 'Original start kept');
      Assert.isTrue(moved.Rescheduled__c, 'Flagged as rescheduled');
      TimetableController.reschedule(
        sessionId,
        start.addHours(1).addMinutes(30),
        start.addHours(2).addMinutes(30),
        null,
        'Again'
      );
      Assert.areEqual(
        start,
        [SELECT Original_Start__c FROM Class_Session__c WHERE Id = :sessionId]
        .Original_Start__c,
        'First original start preserved'
      );

      try {
        TimetableController.reschedule(
          sessionId,
          start.addHours(3),
          start.addHours(4),
          null,
          'Clash'
        );
        Assert.fail('Conflicting move must fail');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('teacher'), e.getMessage());
      }
      try {
        TimetableController.reschedule(sessionId, start, start, null, null);
        Assert.fail('Invalid times');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('valid'), e.getMessage());
      }
      try {
        TimetableController.cancelSession(blockerId, null);
        Assert.fail('Reason required');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('reason'), e.getMessage());
      }
      TimetableController.cancelSession(blockerId, 'Teacher unwell');
      Assert.isFalse(
        TimetableController.previewMove(
            sessionId,
            start.addHours(3),
            start.addHours(4),
            null
          )
          .blocked,
        'Cancelled sessions free the slot'
      );
      try {
        TimetableController.reschedule(
          blockerId,
          start,
          start.addHours(1),
          null,
          'x'
        );
        Assert.fail('Cancelled sessions cannot move');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('Cancelled'), e.getMessage());
      }
      try {
        TimetableController.cancelSession(blockerId, 'Again');
        Assert.fail('Already cancelled');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('scheduled'), e.getMessage());
      }
    }
  }

  @IsTest
  static void warnsAboutLearnerClashes() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      insert new Fee_Price__c(
        Learning_Course__c = f.offering.LearningCourseId,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 100,
        Effective_From__c = Date.today().addDays(-1)
      );
      LearningCourse otherCourse = TestDataFactory.createCourse('Music');
      insert new Fee_Price__c(
        Learning_Course__c = otherCourse.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 100,
        Effective_From__c = Date.today().addDays(-1)
      );
      CourseOffering music = TestDataFactory.createOffering(
        otherCourse.Id,
        f.branch.Id,
        10
      );
      Account learner = PersonAccountService.buildPerson(
        'Kid',
        'TwoClasses',
        null,
        null,
        f.branch.Id,
        'Learner'
      );
      insert learner;
      for (Id offeringId : new List<Id>{ f.offering.Id, music.Id }) {
        EnrolmentService.EnrolmentRequest r = new EnrolmentService.EnrolmentRequest();
        r.learnerAccountId = learner.Id;
        r.offeringId = offeringId;
        EnrolmentService.enrol(r);
      }
      Datetime start = Datetime.newInstance(
        nextMonday(),
        Time.newInstance(16, 0, 0, 0)
      );
      TimetableController.addSession(
        music.Id,
        start,
        start.addHours(1),
        'Class',
        null
      );
      Id geometry = TimetableController.addSession(
        f.offering.Id,
        start.addHours(2),
        start.addHours(3),
        'Class',
        null
      );
      TimetableController.MovePreview preview = TimetableController.previewMove(
        geometry,
        start,
        start.addHours(1),
        null
      );
      Assert.isFalse(preview.blocked, 'Learner clashes warn but do not block');
      Assert.areEqual(1, preview.conflicts.size(), 'One learner clash');
      Assert.areEqual('Learner', preview.conflicts[0].kind, 'Learner conflict');
    }
  }

  @IsTest
  static void timetableViewsAndFilters() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      TestDataFactory.assignToBranch(f.teacher.Id, f.branch.Id, 'Teacher');
      Date monday = nextMonday();
      Datetime start = Datetime.newInstance(
        monday,
        Time.newInstance(9, 0, 0, 0)
      );
      TimetableController.addSession(
        f.offering.Id,
        start,
        start.addHours(1),
        'Class',
        null
      );
      Assert.areEqual(
        1,
        TimetableController.getWeek(
            monday.toStartOfWeek(),
            f.branch.Id,
            f.teacher.Id,
            f.room.Id
          )
          .size(),
        'Session in its week with all filters'
      );
      Assert.areEqual(
        0,
        TimetableController.getWeek(
            monday.toStartOfWeek().addDays(7),
            null,
            null,
            null
          )
          .size(),
        'Nothing the following week'
      );
      TimetableController.Filters filters = TimetableController.getFilters();
      Assert.isFalse(filters.branches.isEmpty(), 'Branches');
      Assert.areEqual(1, filters.teachers.size(), 'Teacher listed once');
      Assert.isFalse(filters.rooms.isEmpty(), 'Rooms');
      try {
        TimetableController.generateSessions(f.offering.Id);
        Assert.fail('No pattern yet');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('weekly pattern'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void teacherSeesTimetableButCannotMoveSessions() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture();
      Datetime start = Datetime.newInstance(
        nextMonday(),
        Time.newInstance(9, 0, 0, 0)
      );
      Id sessionId = TimetableController.addSession(
        f.offering.Id,
        start,
        start.addHours(1),
        'Class',
        null
      );
      System.runAs(f.teacher) {
        Assert.areEqual(
          1,
          TimetableController.getWeek(
              start.date().toStartOfWeek(),
              null,
              f.teacher.Id,
              null
            )
            .size(),
          'Teacher sees own session'
        );
        try {
          TimetableController.reschedule(
            sessionId,
            start.addHours(2),
            start.addHours(3),
            null,
            'Prefer later'
          );
          Assert.fail('Teachers cannot reschedule');
        } catch (AuraHandledException e) {
          Assert.isNotNull(e.getMessage(), 'Denied');
        }
      }
    }
  }
}
