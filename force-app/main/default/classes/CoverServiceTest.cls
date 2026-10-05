@IsTest
private class CoverServiceTest {
  /**
   * Teacher A teaches "Cover Class" on day 1 and day 2 (10:00-11:00, room R1,
   * two learners). Teacher B has taught the same course before. Teacher C
   * teaches "C Class" in room R2 on day 1 at 10:30. Room R3 holds one learner.
   */
  @TestSetup
  static void setup() {
    TestDataFactory.createReferenceData();
    List<User> teachers = new List<User>();
    for (Integer i = 0; i < 3; i++) {
      teachers.add(
        TestDataFactory.createUserWithLicense(
          TestDataFactory.persona('KEM_Teacher')
        )
      );
    }
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      for (User teacher : teachers) {
        TestDataFactory.assignToBranch(teacher.Id, branch.Id, 'Teacher');
      }
      List<Room__c> rooms = new List<Room__c>{
        new Room__c(Name = 'R1', Branch__c = branch.Id, Capacity__c = 20),
        new Room__c(Name = 'R2', Branch__c = branch.Id, Capacity__c = 20),
        new Room__c(Name = 'R3', Branch__c = branch.Id, Capacity__c = 1)
      };
      insert rooms;
      LearningCourse course = TestDataFactory.createCourse('Robotics');
      insert new Fee_Price__c(
        Learning_Course__c = course.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Term',
        Amount__c = 1000,
        Effective_From__c = Date.today().addDays(-5)
      );
      List<CourseOffering> classes = new List<CourseOffering>();
      for (
        String name : new List<String>{ 'Cover Class', 'B Class', 'C Class' }
      ) {
        CourseOffering offering = TestDataFactory.createOffering(
          course.Id,
          branch.Id,
          10
        );
        classes.add(offering);
      }
      update new List<CourseOffering>{
        new CourseOffering(
          Id = classes[0].Id,
          Name = 'Cover Class',
          Teacher_User__c = teachers[0].Id
        ),
        new CourseOffering(
          Id = classes[1].Id,
          Name = 'B Class',
          Teacher_User__c = teachers[1].Id
        ),
        new CourseOffering(
          Id = classes[2].Id,
          Name = 'C Class',
          Teacher_User__c = teachers[2].Id
        )
      };
      List<Account> learners = new List<Account>();
      for (Integer i = 0; i < 2; i++) {
        learners.add(
          PersonAccountService.buildPerson(
            'L' + i,
            'Cover' + Crypto.getRandomInteger(),
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
        request.offeringId = classes[0].Id;
        EnrolmentService.enrol(request);
      }
      insert new List<Class_Session__c>{
        session(classes[0], branch, rooms[0], teachers[0], day(1, 10), 60),
        session(classes[0], branch, rooms[0], teachers[0], day(2, 10), 60),
        session(
          classes[2],
          branch,
          rooms[1],
          teachers[2],
          day(1, 10).addMinutes(30),
          60
        )
      };
    }
  }

  private static Datetime day(Integer offset, Integer hour) {
    return Datetime.newInstance(
      Date.today().addDays(offset + 1),
      Time.newInstance(hour, 0, 0, 0)
    );
  }

  private static Class_Session__c session(
    CourseOffering offering,
    Branch__c branch,
    Room__c room,
    User teacher,
    Datetime startAt,
    Integer minutes
  ) {
    return new Class_Session__c(
      Course_Offering__c = offering.Id,
      Branch__c = branch.Id,
      Room__c = room.Id,
      Teacher_User__c = teacher.Id,
      Start__c = startAt,
      End__c = startAt.addMinutes(minutes),
      Status__c = 'Scheduled',
      Session_Type__c = 'Class'
    );
  }

  private static Id teacherOf(String className) {
    return [SELECT Teacher_User__c FROM CourseOffering WHERE Name = :className]
    .Teacher_User__c;
  }

  private static List<Class_Session__c> coverSessions() {
    return [
      SELECT
        Id,
        Status__c,
        Teacher_User__c,
        Original_Teacher__c,
        Needs_Cover__c,
        Teacher_Attendance__c,
        Room__c,
        Original_Room__c,
        Staff_Absence__c
      FROM Class_Session__c
      WHERE Course_Offering__r.Name = 'Cover Class'
      ORDER BY Start__c
    ];
  }

  private static Staff_Absence__c absence(Id absenceId) {
    return [
      SELECT
        Status__c,
        Sessions_Affected__c,
        Sessions_Handled__c,
        Reported_By__c
      FROM Staff_Absence__c
      WHERE Id = :absenceId
    ];
  }

  private static CoverService.AbsenceRequest request(Id teacherId) {
    CoverService.AbsenceRequest r = new CoverService.AbsenceRequest();
    r.teacherId = teacherId;
    r.startAt = day(1, 0);
    r.endAt = day(2, 23);
    r.reason = 'Sick Leave';
    r.notes = 'Fever';
    return r;
  }

  @IsTest
  static void absenceIsCoveredOrCancelled() {
    Id a = teacherOf('Cover Class');
    Id b = teacherOf('B Class');
    Id c = teacherOf('C Class');
    Id absenceId;
    Id firstSession = coverSessions()[0].Id;
    System.runAs(new User(Id = a)) {
      absenceId = CoverController.recordAbsence(request(null));
      try {
        CoverService.recordAbsence(request(b));
        Assert.fail('Teachers report only their own absence');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('own absence'), e.getMessage());
      }
      try {
        CoverService.assignCover(firstSession, b, null);
        Assert.fail('Teachers do not arrange cover');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
    }
    System.runAs(TestDataFactory.admin()) {
      Staff_Absence__c recorded = absence(absenceId);
      Assert.areEqual('Needs Cover', recorded.Status__c, 'Waiting for cover');
      Assert.areEqual(2, recorded.Sessions_Affected__c, 'Both sessions');
      Assert.areEqual(a, recorded.Reported_By__c, 'Reported by the teacher');
      List<Class_Session__c> sessions = coverSessions();
      Assert.isTrue(
        sessions[0].Needs_Cover__c && sessions[1].Needs_Cover__c,
        'Flagged'
      );
      try {
        CoverService.recordAbsence(request(a));
        Assert.fail('Overlapping absence');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already has an absence'),
          e.getMessage()
        );
      }

      Test.startTest();
      CoverService.CoverDesk desk = CoverController.getDesk();
      Assert.areEqual(1, desk.absences.size(), 'Absence listed');
      Assert.areEqual(2, desk.uncovered.size(), 'Two sessions need cover');
      Assert.isTrue(desk.canArrange, 'Administrator arranges cover');
      Assert.areEqual(2, desk.uncovered[0].learners, 'Learner count');
      List<CoverService.Candidate> ranked = desk.uncovered[0].candidates;
      Assert.areEqual(2, ranked.size(), 'B and C, not the absent teacher');
      Assert.areEqual(b, ranked[0].userId, 'Free and has taught the course');
      Assert.isTrue(ranked[0].taughtCourse, 'Experience counted');
      Assert.isFalse(ranked[1].free, 'C is teaching at that time');
      Assert.isTrue(ranked[1].clash.contains('C Class'), ranked[1].clash);
      Assert.areEqual(
        ranked[0].userId,
        CoverController.getCandidates(sessions[0].Id)[0].userId,
        'Same ranking for one session'
      );

      try {
        CoverService.assignCover(sessions[0].Id, c, null);
        Assert.fail('C is double-booked');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already teaching'),
          e.getMessage()
        );
      }
      CoverController.assignCover(sessions[0].Id, b, 'Covering for A');
      Class_Session__c covered = coverSessions()[0];
      Assert.areEqual(b, covered.Teacher_User__c, 'Cover teacher');
      Assert.areEqual(a, covered.Original_Teacher__c, 'Original kept');
      Assert.isFalse(covered.Needs_Cover__c, 'Covered');
      Assert.areEqual(
        'Substituted',
        covered.Teacher_Attendance__c,
        'Marked substituted'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Task WHERE WhatId = :covered.Id AND OwnerId = :b],
        'Cover teacher told'
      );
      Assert.areEqual(
        'Partially Covered',
        absence(absenceId).Status__c,
        'One left'
      );

      CoverController.cancelForAbsence(sessions[1].Id, 'No cover available');
      Assert.areEqual('Cancelled', coverSessions()[1].Status__c, 'Cancelled');
      Staff_Absence__c handled = absence(absenceId);
      Assert.areEqual('Covered', handled.Status__c, 'All handled');
      Assert.areEqual(2, handled.Sessions_Handled__c, 'Two handled');

      CoverController.withdrawAbsence(absenceId);
      Assert.areEqual('Withdrawn', absence(absenceId).Status__c, 'Withdrawn');
      try {
        CoverService.withdrawAbsence(absenceId);
        Assert.fail('Already withdrawn');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('already'), e.getMessage());
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void withdrawingReleasesUncoveredSessions() {
    Id a = teacherOf('Cover Class');
    System.runAs(TestDataFactory.admin()) {
      Id absenceId = CoverService.recordAbsence(request(a));
      CoverService.withdrawAbsence(absenceId);
      for (Class_Session__c s : coverSessions()) {
        Assert.isFalse(s.Needs_Cover__c, 'Back with the teacher');
        Assert.areEqual(a, s.Teacher_User__c, 'Unchanged');
      }
    }
  }

  @IsTest
  static void roomSwapChecksCapacityAndAvailability() {
    System.runAs(TestDataFactory.admin()) {
      List<Class_Session__c> sessions = coverSessions();
      Map<String, Id> rooms = new Map<String, Id>();
      for (Room__c room : [SELECT Id, Name FROM Room__c]) {
        rooms.put(room.Name, room.Id);
      }
      List<CoverService.RoomOption> day1 = CoverController.getRoomOptions(
        sessions[0].Id
      );
      Assert.areEqual(2, day1.size(), 'R2 and R3');
      for (CoverService.RoomOption option : day1) {
        if (option.name == 'R2') {
          Assert.isFalse(option.free, 'R2 is booked for C Class on day 1');
        } else {
          Assert.isFalse(option.bigEnough, 'R3 holds one learner');
        }
      }
      List<CoverService.RoomOption> day2 = CoverService.roomOptions(
        sessions[1].Id
      );
      Assert.areEqual('R2', day2[0].name, 'Free and big enough first');
      Assert.isTrue(day2[0].free && day2[0].bigEnough, 'Usable');

      try {
        CoverService.swapRoom(sessions[1].Id, rooms.get('R3'), null);
        Assert.fail('Too small');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('2 learners'), e.getMessage());
      }
      try {
        CoverService.swapRoom(sessions[0].Id, rooms.get('R2'), null);
        Assert.fail('Double-booked room');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already booked'),
          e.getMessage()
        );
      }
      CoverController.swapRoom(
        sessions[1].Id,
        rooms.get('R2'),
        'Projector broken in R1'
      );
      Class_Session__c moved = coverSessions()[1];
      Assert.areEqual(rooms.get('R2'), moved.Room__c, 'Moved');
      Assert.areEqual(rooms.get('R1'), moved.Original_Room__c, 'Original kept');
      CoverService.swapRoom(sessions[1].Id, rooms.get('R1'), null);
      Assert.isNull(
        coverSessions()[1].Original_Room__c,
        'Back in its own room'
      );
    }
  }

  @IsTest
  static void validationAndControllerErrors() {
    System.runAs(TestDataFactory.admin()) {
      Id sessionId = coverSessions()[0].Id;
      List<CoverService.AbsenceRequest> invalid = new List<CoverService.AbsenceRequest>{
        null,
        request(null),
        request(null)
      };
      invalid[1].endAt = invalid[1].startAt;
      invalid[2].reason = null;
      Integer failures = 0;
      for (CoverService.AbsenceRequest r : invalid) {
        try {
          CoverController.recordAbsence(r);
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Id fakeSession = TestUtil.fakeId(Class_Session__c.SObjectType);
      for (Integer i = 0; i < 7; i++) {
        try {
          switch on i {
            when 0 {
              CoverController.assignCover(sessionId, null, null);
            }
            when 1 {
              CoverController.swapRoom(sessionId, null, null);
            }
            when 2 {
              CoverController.getCandidates(fakeSession);
            }
            when 3 {
              CoverController.getRoomOptions(fakeSession);
            }
            when 4 {
              CoverController.withdrawAbsence(
                TestUtil.fakeId(Staff_Absence__c.SObjectType)
              );
            }
            when 5 {
              CoverController.assignCover(
                sessionId,
                [
                  SELECT Teacher_User__c
                  FROM Class_Session__c
                  WHERE Id = :sessionId
                ]
                .Teacher_User__c,
                null
              );
            }
            when 6 {
              CoverController.cancelForAbsence(fakeSession, null);
            }
          }
        } catch (AuraHandledException e) {
          failures++;
        }
      }
      Assert.areEqual(10, failures, 'Every rule enforced');
      CoverService.Candidate x = new CoverService.Candidate();
      x.name = 'X';
      x.free = true;
      x.taughtCourse = false;
      x.sessionsThatDay = 3;
      CoverService.Candidate y = new CoverService.Candidate();
      y.name = 'Y';
      y.free = true;
      y.taughtCourse = false;
      y.sessionsThatDay = 1;
      Assert.areEqual(
        'Y',
        CoverService.sortCandidates(new List<CoverService.Candidate>{ x, y })[0]
          .name,
        'Lighter load first'
      );
    }
  }
}
