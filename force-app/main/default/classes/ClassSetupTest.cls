@IsTest
private class ClassSetupTest {
  private class Fixture {
    Branch__c branch;
    Room__c room;
    Room__c smallRoom;
    LearningCourse course;
    Id classId;
  }

  /** A class with two weeks of daily sessions from tomorrow, no teacher or room. */
  private static Fixture fixture(String name) {
    Fixture f = new Fixture();
    f.branch = TestDataFactory.createBranch();
    f.room = TestDataFactory.createRoom(f.branch.Id, 12);
    f.smallRoom = TestDataFactory.createRoom(f.branch.Id, 4);
    f.course = TestDataFactory.createCourse(name);
    f.classId = newClass(f, '16:30', null);
    return f;
  }

  private static Id newClass(Fixture f, String startTime, Id teacher) {
    CatalogSetupService.PatternLine p = new CatalogSetupService.PatternLine();
    p.days = new List<String>{
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun'
    };
    p.startTime = startTime;
    p.minutes = 60;
    CatalogSetupService.ClassRequest r = new CatalogSetupService.ClassRequest();
    r.courseId = f.course.Id;
    r.branchId = f.branch.Id;
    r.capacity = 10;
    r.teacherUserId = teacher;
    r.deliveryMode = 'Online';
    r.startDate = Date.today().addDays(1);
    r.endDate = Date.today().addDays(14);
    r.openForEnrolment = true;
    r.patterns = new List<CatalogSetupService.PatternLine>{ p };
    return CatalogSetupService.createClass(r).classId;
  }

  private static ClassSetupService.SaveRequest request(Fixture f) {
    ClassSetupService.SaveRequest r = new ClassSetupService.SaveRequest();
    r.classId = f.classId;
    r.branchId = f.branch.Id;
    r.capacity = 10;
    r.deliveryMode = 'Classroom';
    r.status = 'Open';
    return r;
  }

  @IsTest
  static void assigningATeacherAndRoomReachesTheUpcomingSessions() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture('Robotics Club');
      insert new Branch_Staff__c(
        Branch__c = f.branch.Id,
        User__c = UserInfo.getUserId(),
        Role__c = 'Teacher',
        Active__c = true
      );
      ClassSetupService.Details before = ClassSetupController.getDetails(
        f.classId,
        null
      );
      Assert.areEqual(14, before.upcomingSessions, 'Sessions');
      Assert.areEqual(14, before.upcomingWithoutTeacher, 'No teacher yet');
      Assert.areEqual(1, before.patterns, 'Weekly pattern');
      Assert.areEqual(1, before.teachers.size(), 'Branch teacher offered');
      Assert.areEqual(2, before.rooms.size(), 'Rooms offered');
      Assert.isFalse(before.statuses.isEmpty(), 'Statuses');

      ClassSetupService.SaveRequest r = request(f);
      r.teacherUserId = UserInfo.getUserId();
      r.roomId = f.room.Id;
      Test.startTest();
      ClassSetupService.Propagation p = ClassSetupController.saveClass(r);
      Test.stopTest();
      Assert.areEqual(14, p.updated, 'Every upcoming session updated');
      Assert.isTrue(p.clashes.isEmpty(), 'No clashes');
      Assert.areEqual(
        14,
        [
          SELECT COUNT()
          FROM Class_Session__c
          WHERE
            Course_Offering__c = :f.classId
            AND Teacher_User__c = :UserInfo.getUserId()
            AND Room__c = :f.room.Id
        ],
        'Sessions follow the class'
      );
      CourseOffering o = [
        SELECT Teacher_User__c, Room__c, Delivery_Mode__c
        FROM CourseOffering
        WHERE Id = :f.classId
      ];
      Assert.areEqual(UserInfo.getUserId(), o.Teacher_User__c, 'Class teacher');
      Assert.areEqual('Classroom', o.Delivery_Mode__c, 'Delivery');
      Assert.areEqual(
        0,
        ClassSetupService.details(f.classId, null).upcomingWithoutTeacher,
        'Gap closed'
      );
    }
  }

  @IsTest
  static void clashingSessionsKeepTheirTeacherAndAreReported() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture('Chess Club');
      // The same teacher already teaches another class at the same times.
      Id busyTeacher = UserInfo.getUserId();
      newClass(f, '16:30', busyTeacher);
      ClassSetupService.SaveRequest r = request(f);
      r.teacherUserId = busyTeacher;
      Test.startTest();
      ClassSetupService.Propagation p = ClassSetupService.save(r);
      Test.stopTest();
      Assert.areEqual(0, p.updated, 'No session could take the teacher');
      Assert.areEqual(14, p.clashes.size(), 'Every clash reported');
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Class_Session__c
          WHERE Course_Offering__c = :f.classId AND Teacher_User__c != NULL
        ],
        'Sessions kept their (empty) teacher'
      );
      Assert.areEqual(
        busyTeacher,
        [SELECT Teacher_User__c FROM CourseOffering WHERE Id = :f.classId]
        .Teacher_User__c,
        'Class saved'
      );
    }
  }

  @IsTest
  static void standardEditsAlsoReachSessionsButNotCoveredOnes() {
    User deployer = new User(Id = UserInfo.getUserId());
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture('Art Club');
      Class_Session__c covered = [
        SELECT Id
        FROM Class_Session__c
        WHERE Course_Offering__c = :f.classId
        ORDER BY Start__c
        LIMIT 1
      ];
      // Needs_Cover__c is system-managed: set it as the deployer.
      System.runAs(deployer) {
        update new Class_Session__c(Id = covered.Id, Needs_Cover__c = true);
      }
      Test.startTest();
      update new CourseOffering(
        Id = f.classId,
        Teacher_User__c = UserInfo.getUserId()
      );
      Test.stopTest();
      Assert.areEqual(
        13,
        [
          SELECT COUNT()
          FROM Class_Session__c
          WHERE
            Course_Offering__c = :f.classId
            AND Teacher_User__c = :UserInfo.getUserId()
        ],
        'All but the session needing cover'
      );
      Assert.isNull(
        [SELECT Teacher_User__c FROM Class_Session__c WHERE Id = :covered.Id]
        .Teacher_User__c,
        'Cover untouched'
      );
    }
  }

  @IsTest
  static void refusesBadChanges() {
    System.runAs(TestDataFactory.admin()) {
      Fixture f = fixture('Music Club');
      Branch__c other = TestDataFactory.createBranch();
      Room__c elsewhere = TestDataFactory.createRoom(other.Id, 30);
      ClassSetupService.SaveRequest small = request(f);
      small.roomId = f.smallRoom.Id;
      ClassSetupService.SaveRequest away = request(f);
      away.roomId = elsewhere.Id;
      ClassSetupService.SaveRequest noSeats = request(f);
      noSeats.capacity = 0;
      ClassSetupService.SaveRequest noBranch = request(f);
      noBranch.branchId = null;
      for (
        ClassSetupService.SaveRequest bad : new List<ClassSetupService.SaveRequest>{
          small,
          away,
          noSeats,
          noBranch
        }
      ) {
        try {
          ClassSetupService.save(bad);
          Assert.fail('Expected a refusal');
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      ClassSetupService.Details d = ClassSetupService.details(
        f.classId,
        other.Id
      );
      Assert.areEqual(1, d.rooms.size(), 'Rooms of the chosen branch');
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        ClassSetupController.saveClass(new ClassSetupService.SaveRequest());
        Assert.fail('Teachers do not change classes');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        ClassSetupController.getDetails(null, null);
        Assert.fail('Nothing to show');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Explained');
      }
    }
  }
}
