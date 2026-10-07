@IsTest
private class CatalogSetupTest {
  private static CatalogSetupService.PriceLine price(
    String feeType,
    String frequency,
    Decimal amount
  ) {
    CatalogSetupService.PriceLine p = new CatalogSetupService.PriceLine();
    p.feeType = feeType;
    p.frequency = frequency;
    p.amount = amount;
    return p;
  }

  private static CatalogSetupService.CourseRequest course(
    String name,
    String code
  ) {
    CatalogSetupService.CourseRequest r = new CatalogSetupService.CourseRequest();
    r.name = name;
    r.code = code;
    r.description = 'Hands-on lessons';
    r.minAge = 8;
    r.maxAge = 12;
    r.prices = new List<CatalogSetupService.PriceLine>{
      price('Tuition', 'Monthly', 2500),
      price('Admission', 'One-time', 1000)
    };
    return r;
  }

  /** Every day from tomorrow for two weeks at 16:30 for an hour. */
  private static CatalogSetupService.ClassRequest classFor(
    Id courseId,
    Id branchId,
    Id roomId
  ) {
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
    p.startTime = '16:30';
    p.minutes = 60;
    CatalogSetupService.ClassRequest r = new CatalogSetupService.ClassRequest();
    r.courseId = courseId;
    r.branchId = branchId;
    r.roomId = roomId;
    r.capacity = 10;
    r.teacherUserId = UserInfo.getUserId();
    r.startDate = Date.today().addDays(1);
    r.endDate = Date.today().addDays(14);
    r.openForEnrolment = true;
    r.patterns = new List<CatalogSetupService.PatternLine>{ p };
    return r;
  }

  @IsTest
  static void createsCourseWithPricesAndRefusesDuplicates() {
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      Id courseId = CatalogSetupController.createCourse(
        course('Chess for Beginners', 'kt-crs-chs')
      );
      Test.stopTest();

      LearningCourse saved = [
        SELECT Name, External_ID__c, Minimum_Age__c, Maximum_Age__c, LearningId
        FROM LearningCourse
        WHERE Id = :courseId
      ];
      Assert.areEqual('KT-CRS-CHS', saved.External_ID__c, 'Code upper-cased');
      Assert.areEqual(8, saved.Minimum_Age__c.intValue(), 'Minimum age');
      Assert.isNotNull(saved.LearningId, 'Learning record');
      List<Fee_Price__c> prices = [
        SELECT Fee_Type__c, Amount__c, Description__c, Effective_From__c
        FROM Fee_Price__c
        WHERE Learning_Course__c = :courseId
        ORDER BY Amount__c DESC
      ];
      Assert.areEqual(2, prices.size(), 'Two prices');
      Assert.areEqual('Monthly tuition', prices[0].Description__c, 'Named');
      Assert.areEqual(Date.today(), prices[0].Effective_From__c, 'From today');

      Integer learnings = [SELECT COUNT() FROM Learning];
      for (
        CatalogSetupService.CourseRequest bad : new List<CatalogSetupService.CourseRequest>{
          course('Another Name', 'KT-CRS-CHS'),
          course('Chess for Beginners', 'KT-CRS-NEW'),
          course('', null)
        }
      ) {
        try {
          CatalogSetupService.createCourse(bad);
          Assert.fail('Expected a refusal for ' + bad.name);
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      CatalogSetupService.CourseRequest ages = course('Ages Wrong', null);
      ages.minAge = 14;
      try {
        CatalogSetupService.createCourse(ages);
        Assert.fail('Ages must be in order');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('minimum age'), e.getMessage());
      }
      CatalogSetupService.CourseRequest free = course('Free Price', null);
      free.prices[0].amount = 0;
      try {
        CatalogSetupService.createCourse(free);
        Assert.fail('Prices must be above zero');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('above zero'), e.getMessage());
      }
      Assert.areEqual(
        learnings,
        [SELECT COUNT() FROM Learning],
        'Nothing half-saved'
      );
    }
  }

  @IsTest
  static void previewSavesNothingAndCreateBuildsTheTimetable() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Room__c room = TestDataFactory.createRoom(branch.Id, 12);
      LearningCourse c = TestDataFactory.createCourse('Robotics Club');
      insert new Branch_Staff__c(
        Branch__c = branch.Id,
        User__c = UserInfo.getUserId(),
        Role__c = 'Teacher',
        Active__c = true
      );
      insert new Calendar_Closure__c(
        Name = 'Founders Day',
        Branch__c = branch.Id,
        Start_Date__c = Date.today().addDays(5),
        End_Date__c = Date.today().addDays(5),
        Closure_Type__c = 'Public Holiday'
      );

      CatalogSetupService.Choices choices = CatalogSetupController.getChoices();
      Assert.isFalse(choices.courses.isEmpty(), 'Courses offered');
      CatalogSetupService.BranchChoices bc = CatalogSetupController.getBranchChoices(
        branch.Id
      );
      Assert.areEqual(1, bc.rooms.size(), 'Room offered');
      Assert.isTrue(bc.rooms[0].label.contains('12 seats'), bc.rooms[0].label);
      Assert.areEqual(1, bc.teachers.size(), 'Teacher offered');

      Test.startTest();
      CatalogSetupService.ClassPreview preview = CatalogSetupController.previewClass(
        classFor(c.Id, branch.Id, room.Id)
      );
      Assert.areEqual(13, preview.sessions, 'Fourteen days less the holiday');
      Assert.areEqual(1, preview.skippedHolidays, 'Holiday skipped');
      Assert.areEqual(4, preview.firstSessions.size(), 'First sessions');
      Assert.isNull(preview.classId, 'Preview has no class');
      Assert.isTrue(
        String.join(preview.warnings, ' ').contains('no tuition price'),
        String.join(preview.warnings, ' ')
      );
      Assert.areEqual(0, [SELECT COUNT() FROM CourseOffering], 'Nothing saved');
      Assert.areEqual(0, [SELECT COUNT() FROM Class_Session__c], 'No sessions');

      CatalogSetupService.ClassPreview created = CatalogSetupController.createClass(
        classFor(c.Id, branch.Id, room.Id)
      );
      // A second class in the same room at the same time clashes.
      CatalogSetupService.ClassPreview clash = CatalogSetupController.previewClass(
        classFor(c.Id, branch.Id, room.Id)
      );
      // Creating it would give a class with no sessions, so it is refused.
      try {
        CatalogSetupController.createClass(classFor(c.Id, branch.Id, room.Id));
        Assert.fail('Every session clashes');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('No sessions'), e.getMessage());
      }
      Test.stopTest();

      CourseOffering o = [
        SELECT Name, Class_Status__c, Room__c, EnrollmentCapacity
        FROM CourseOffering
        WHERE Id = :created.classId
      ];
      Assert.isTrue(o.Name.startsWith('Robotics Club – Monday'), o.Name);
      Assert.areEqual('Open', o.Class_Status__c, 'Open for enrolment');
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM CourseOfferingSchedule
          WHERE CourseOfferingId = :o.Id
        ],
        'Pattern'
      );
      Assert.areEqual(
        13,
        [SELECT COUNT() FROM Class_Session__c WHERE Course_Offering__c = :o.Id],
        'Sessions'
      );
      Assert.isFalse(clash.clashes.isEmpty(), 'Room and teacher clash shown');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM CourseOffering],
        'Clash preview saved nothing'
      );
    }
  }

  @IsTest
  static void checksRoomAndInputs() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c branch = TestDataFactory.createBranch();
      Branch__c other = TestDataFactory.createBranch();
      Room__c small = TestDataFactory.createRoom(branch.Id, 6);
      Room__c elsewhere = TestDataFactory.createRoom(other.Id, 20);
      LearningCourse c = TestDataFactory.createCourse('Spoken English');

      CatalogSetupService.ClassRequest tooBig = classFor(
        c.Id,
        branch.Id,
        small.Id
      );
      try {
        CatalogSetupService.previewClass(tooBig);
        Assert.fail('Room too small');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('seats 6'), e.getMessage());
      }
      try {
        CatalogSetupService.createClass(
          classFor(c.Id, branch.Id, elsewhere.Id)
        );
        Assert.fail('Room at another branch');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('another branch'),
          e.getMessage()
        );
      }
      CatalogSetupService.ClassRequest badTime = classFor(
        c.Id,
        branch.Id,
        null
      );
      badTime.patterns[0].startTime = 'evening';
      try {
        CatalogSetupService.createClass(badTime);
        Assert.fail('Time format');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('16:30'), e.getMessage());
      }
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM CourseOffering],
        'Failed creates roll back'
      );

      CatalogSetupService.ClassRequest noRoom = classFor(c.Id, branch.Id, null);
      noRoom.teacherUserId = null;
      noRoom.openForEnrolment = false;
      noRoom.name = 'Spoken English – Evening';
      CatalogSetupService.ClassPreview p = CatalogSetupService.createClass(
        noRoom
      );
      String warnings = String.join(p.warnings, ' ');
      Assert.isTrue(warnings.contains('No room'), warnings);
      Assert.isTrue(warnings.contains('No teacher'), warnings);
      Assert.areEqual(
        'Planned',
        [SELECT Class_Status__c FROM CourseOffering WHERE Id = :p.classId]
        .Class_Status__c,
        'Not yet open'
      );
    }
  }

  @IsTest
  static void addsFacultyOnce() {
    System.runAs(TestDataFactory.admin()) {
      CatalogSetupService.FacultyRequest f = new CatalogSetupService.FacultyRequest();
      f.firstName = 'Meera';
      f.lastName = 'Pillai';
      f.email = 'Meera.Pillai@example.com';
      f.subject = 'Robotics';
      Test.startTest();
      Id first = CatalogSetupController.createFaculty(f);
      Test.stopTest();
      Contact saved = [
        SELECT Title, Email, Account.Name
        FROM Contact
        WHERE Id = :first
      ];
      Assert.areEqual('Faculty – Robotics', saved.Title, 'Title');
      Assert.areEqual('meera.pillai@example.com', saved.Email, 'Email');
      Assert.areEqual(
        CatalogSetupService.facultyAccountName(),
        saved.Account.Name,
        'Faculty account'
      );
      Assert.areEqual(
        1,
        CatalogSetupService.choices().faculty.size(),
        'Offered on classes'
      );
      try {
        CatalogSetupService.createFaculty(f);
        Assert.fail('Duplicate email');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already exists'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void teachersCannotCreateCourses() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        CatalogSetupController.createCourse(course('Teacher Course', null));
        Assert.fail('Teachers do not create courses');
      } catch (Exception e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
    }
  }

  @IsTest
  static void controllerExplainsRefusals() {
    System.runAs(TestDataFactory.admin()) {
      Integer refused = 0;
      try {
        CatalogSetupController.createCourse(
          new CatalogSetupService.CourseRequest()
        );
      } catch (AuraHandledException e) {
        refused++;
      }
      try {
        CatalogSetupController.previewClass(
          new CatalogSetupService.ClassRequest()
        );
      } catch (AuraHandledException e) {
        refused++;
      }
      try {
        CatalogSetupController.createClass(
          new CatalogSetupService.ClassRequest()
        );
      } catch (AuraHandledException e) {
        refused++;
      }
      try {
        CatalogSetupController.createFaculty(
          new CatalogSetupService.FacultyRequest()
        );
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('last name'), e.getMessage());
        refused++;
      }
      Assert.areEqual(4, refused, 'Each refusal explained');
      Assert.isTrue(
        CatalogSetupController.getBranchChoices(null).rooms.isEmpty(),
        'No branch, no rooms'
      );
    }
  }
}
