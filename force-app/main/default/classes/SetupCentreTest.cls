@IsTest
private class SetupCentreTest {
  private static SetupCentreService.Tile tile(
    SetupCentreService.Centre c,
    String key
  ) {
    for (SetupCentreService.Tile t : c.tiles) {
      if (t.key == key) {
        return t;
      }
    }
    return null;
  }

  private static SetupCentreService.Gap gap(
    SetupCentreService.Centre c,
    String key
  ) {
    for (SetupCentreService.Gap g : c.gaps) {
      if (g.key == key) {
        return g;
      }
    }
    return null;
  }

  @IsTest
  static void administratorsSeeCountsAndGaps() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c ready = TestDataFactory.buildBranch();
      ready.Branch_Code__c = 'SC-READY';
      ready.Branch_Manager__c = UserInfo.getUserId();
      Branch__c bare = TestDataFactory.buildBranch();
      bare.Name = 'Bare Centre';
      bare.Branch_Code__c = 'SC-BARE';
      insert new List<Branch__c>{ ready, bare };
      Room__c room = TestDataFactory.createRoom(ready.Id, 12);
      LearningCourse priced = TestDataFactory.createCourse('Priced Course');
      LearningCourse unpriced = TestDataFactory.createCourse('Unpriced Course');
      insert new Fee_Price__c(
        Learning_Course__c = priced.Id,
        Fee_Type__c = 'Tuition',
        Billing_Frequency__c = 'Monthly',
        Amount__c = 2000,
        Effective_From__c = Date.today().addDays(-10),
        Active__c = true
      );
      // A class missing its teacher, room and sessions; another without a branch or seat limit.
      CourseOffering gaps = TestDataFactory.createOffering(
        priced.Id,
        ready.Id,
        10
      );
      CourseOffering loose = new CourseOffering(
        Name = 'No Branch Class',
        LearningCourseId = unpriced.Id,
        Delivery_Mode__c = 'Online',
        Class_Status__c = 'Planned'
      );
      insert loose;
      insert new Calendar_Closure__c(
        Name = 'Founders Day',
        Branch__c = ready.Id,
        Start_Date__c = Date.today().addDays(5),
        End_Date__c = Date.today().addDays(5),
        Closure_Type__c = 'Public Holiday'
      );

      Test.startTest();
      SetupCentreService.Centre centre = SetupCentreController.getCentre();
      Test.stopTest();

      Assert.areEqual(2, tile(centre, 'branches').count, 'Active branches');
      Assert.isTrue(
        tile(centre, 'branches').canCreate,
        'Administrators create branches'
      );
      Assert.areEqual(1, tile(centre, 'rooms').count, 'Rooms');
      Assert.areEqual('12 seats', tile(centre, 'rooms').detail, 'Seats');
      Assert.areEqual(2, tile(centre, 'classes').count, 'Current classes');
      Assert.areEqual(
        '1 running · 1 planned',
        tile(centre, 'classes').detail,
        'Class split'
      );
      Assert.isTrue(
        tile(centre, 'holidays').detail.contains('Founders Day'),
        tile(centre, 'holidays').detail
      );
      Assert.isNotNull(tile(centre, 'portal'), 'Portal tile');
      Assert.isTrue(tile(centre, 'courses').wizard, 'Course wizard');
      Assert.isTrue(tile(centre, 'classes').wizard, 'Class wizard');
      Assert.isTrue(tile(centre, 'faculty').canCreate, 'New faculty');
      Assert.isNull(
        tile(centre, 'faculty').objectApiName,
        'Faculty list is the faculty account'
      );

      Assert.areEqual(
        1,
        gap(centre, 'branchRooms').count,
        'Bare centre has no rooms'
      );
      Assert.areEqual(
        'Bare Centre',
        gap(centre, 'branchRooms').records[0].name,
        'Named'
      );
      Assert.areEqual(
        1,
        gap(centre, 'branchManager').count,
        'Bare centre has no manager'
      );
      Assert.areEqual(
        unpriced.Id,
        gap(centre, 'coursePrice').records[0].id,
        'Unpriced course'
      );
      Assert.areEqual(
        2,
        gap(centre, 'classTeacher').count,
        'No teacher on either class'
      );
      Assert.areEqual(
        1,
        gap(centre, 'classBranch').count,
        'Class without a branch'
      );
      Assert.areEqual(
        1,
        gap(centre, 'classRoom').count,
        'Classroom class without a room'
      );
      Assert.areEqual(1, gap(centre, 'classSeats').count, 'No seat limit');
      Assert.areEqual(
        gaps.Id,
        gap(centre, 'classSessions').records[0].id,
        'Running class with no sessions'
      );
      Assert.isTrue(centre.openGaps >= 7, 'Open gaps: ' + centre.openGaps);

      // Fixing a gap removes it.
      update new CourseOffering(
        Id = gaps.Id,
        Room__c = room.Id,
        Teacher_User__c = UserInfo.getUserId()
      );
      SetupCentreService.Centre after = SetupCentreService.centre();
      Assert.areEqual(0, gap(after, 'classRoom').count, 'Room set');
      Assert.areEqual(
        1,
        gap(after, 'classTeacher').count,
        'Only the branchless class lacks a teacher'
      );
    }
  }

  @IsTest
  static void teachersDoNotSeeTheCentre() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        SetupCentreController.getCentre();
        Assert.fail('Teachers have no Set-up Centre');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have access'),
          e.getMessage()
        );
      }
    }
  }
}
