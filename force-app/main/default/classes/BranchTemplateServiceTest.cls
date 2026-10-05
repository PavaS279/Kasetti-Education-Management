@IsTest
private class BranchTemplateServiceTest {
  private class Template {
    Branch__c branch;
    LearningCourse course;
    CourseOffering offering;
    Room__c room;
  }

  private static Template template() {
    Template t = new Template();
    t.branch = TestDataFactory.buildBranch();
    t.branch.Name = 'Indiranagar';
    t.branch.Delivery_Modes__c = 'Classroom';
    insert t.branch;
    t.room = TestDataFactory.createRoom(t.branch.Id, 20);
    t.course = TestDataFactory.createCourse('Robotics');
    insert new Fee_Price__c(
      Learning_Course__c = t.course.Id,
      Branch__c = t.branch.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Monthly',
      Amount__c = 2000,
      Effective_From__c = Date.today().addDays(-30)
    );
    insert new Fee_Price__c(
      Learning_Course__c = t.course.Id,
      Branch__c = t.branch.Id,
      Fee_Type__c = 'Tuition',
      Billing_Frequency__c = 'Monthly',
      Amount__c = 1800,
      Effective_From__c = Date.today().addYears(-2),
      Effective_To__c = Date.today().addYears(-1)
    );
    insert new Discount__c(
      Name = 'Sibling',
      Code__c = 'SIB10',
      Discount_Type__c = 'Percentage',
      Value__c = 10,
      Applies_To_Branch__c = t.branch.Id
    );
    insert new Calendar_Closure__c(
      Name = 'Diwali',
      Branch__c = t.branch.Id,
      Start_Date__c = Date.today().addDays(20),
      End_Date__c = Date.today().addDays(22)
    );
    insert new Calendar_Closure__c(
      Name = 'Past',
      Branch__c = t.branch.Id,
      Start_Date__c = Date.today().addDays(-20),
      End_Date__c = Date.today().addDays(-19)
    );
    t.offering = TestDataFactory.createOffering(t.course.Id, t.branch.Id, 15);
    update new CourseOffering(
      Id = t.offering.Id,
      Name = 'Robotics Indiranagar Mon',
      Room__c = t.room.Id,
      Teacher_User__c = UserInfo.getUserId()
    );
    insert new CourseOfferingSchedule(
      CourseOfferingId = t.offering.Id,
      Description = 'Mondays 16:00',
      IsMonday = true,
      StartTime = Time.newInstance(16, 0, 0, 0),
      EndTime = Time.newInstance(17, 0, 0, 0),
      StartDate = Date.today().addDays(-7)
    );
    CourseOffering cancelled = TestDataFactory.createOffering(
      t.course.Id,
      t.branch.Id,
      10
    );
    update new CourseOffering(Id = cancelled.Id, Class_Status__c = 'Cancelled');
    return t;
  }

  private static BranchTemplateService.CloneRequest request(
    Id sourceId,
    String code
  ) {
    BranchTemplateService.CloneRequest r = new BranchTemplateService.CloneRequest();
    r.sourceBranchId = sourceId;
    r.name = 'Whitefield';
    r.code = code;
    r.city = 'Bengaluru';
    r.invoicePrefix = 'WFD';
    r.includeRooms = true;
    r.includePrices = true;
    r.includeDiscounts = true;
    r.includeClosures = true;
    r.includeClasses = true;
    r.classStartDate = Date.today().addDays(30);
    return r;
  }

  @IsTest
  static void previewCountsWhatWillBeCopied() {
    System.runAs(TestDataFactory.admin()) {
      Template t = template();
      Test.startTest();
      BranchTemplateService.Preview p = BranchController.getTemplatePreview(
        t.branch.Id
      );
      Test.stopTest();
      Assert.areEqual('Indiranagar', p.name, 'Name');
      Assert.areEqual(1, p.rooms, 'Rooms');
      Assert.areEqual(1, p.prices, 'Current branch price only');
      Assert.areEqual(1, p.discounts, 'Branch discount');
      Assert.areEqual(1, p.closures, 'Upcoming closure only');
      Assert.areEqual(1, p.classes, 'Running classes only');
      Assert.areEqual(1, p.patterns, 'Weekly pattern');
      Assert.isTrue(p.canCreate, 'Admin can open branches');
      Assert.areEqual(
        Date.today().addMonths(1).toStartOfMonth(),
        p.suggestedStart,
        'Started classes suggest next month'
      );
    }
  }

  @IsTest
  static void cloneCopiesSetUpAsPlannedBranch() {
    System.runAs(TestDataFactory.admin()) {
      Template t = template();
      Test.startTest();
      BranchTemplateService.CloneResult result = BranchController.cloneBranch(
        request(t.branch.Id, 'wfd-01')
      );
      Test.stopTest();

      Branch__c branch = [
        SELECT
          Name,
          Branch_Code__c,
          Invoice_Prefix__c,
          Tax_Rate__c,
          Invoice_Due_Days__c,
          Attendance_Threshold__c,
          Delivery_Modes__c,
          City__c
        FROM Branch__c
        WHERE Id = :result.branchId
      ];
      Assert.areEqual('WFD-01', branch.Branch_Code__c, 'Code upper-cased');
      Assert.areEqual('WFD', branch.Invoice_Prefix__c, 'Own prefix');
      Assert.areEqual(18, branch.Tax_Rate__c, 'Tax policy copied');
      Assert.areEqual(10, branch.Invoice_Due_Days__c, 'Due days copied');
      Assert.areEqual(80, branch.Attendance_Threshold__c, 'Threshold copied');
      Assert.areEqual('Classroom', branch.Delivery_Modes__c, 'Modes copied');
      Assert.areEqual('Bengaluru', branch.City__c, 'City');

      Assert.areEqual(1, result.rooms, 'Rooms');
      Assert.areEqual(1, result.prices, 'Prices');
      Assert.areEqual(1, result.discounts, 'Discounts');
      Assert.areEqual(1, result.closures, 'Closures');
      Assert.areEqual(1, result.classes, 'Classes');
      Assert.areEqual(1, result.patterns, 'Patterns');

      Room__c room = [
        SELECT Id, Capacity__c
        FROM Room__c
        WHERE Branch__c = :result.branchId
      ];
      Assert.areEqual(20, room.Capacity__c, 'Room capacity');
      Fee_Price__c price = [
        SELECT Amount__c, Learning_Course__c
        FROM Fee_Price__c
        WHERE Branch__c = :result.branchId
      ];
      Assert.areEqual(2000, price.Amount__c, 'Current price copied');
      Discount__c discount = [
        SELECT Code__c, Value__c
        FROM Discount__c
        WHERE Applies_To_Branch__c = :result.branchId
      ];
      Assert.areEqual('SIB10-WFD-01', discount.Code__c, 'New code');
      Assert.areEqual(
        'Diwali',
        [
          SELECT Name
          FROM Calendar_Closure__c
          WHERE Branch__c = :result.branchId
        ]
        .Name,
        'Closure copied'
      );

      CourseOffering copy = [
        SELECT
          Id,
          Name,
          Class_Status__c,
          Room__c,
          Teacher_User__c,
          EnrollmentCapacity,
          StartDate,
          LearningCourseId
        FROM CourseOffering
        WHERE Branch__c = :result.branchId
      ];
      Assert.areEqual('Robotics Whitefield Mon', copy.Name, 'Branch renamed');
      Assert.areEqual('Planned', copy.Class_Status__c, 'Planned');
      Assert.areEqual(room.Id, copy.Room__c, 'Room mapped to the new branch');
      Assert.isNull(copy.Teacher_User__c, 'Teachers not copied');
      Assert.areEqual(15, copy.EnrollmentCapacity, 'Capacity');
      Assert.areEqual(
        Date.today().addDays(30),
        copy.StartDate.date(),
        'Shifted to the new start date'
      );
      CourseOfferingSchedule pattern = [
        SELECT StartDate, StartTime, IsMonday
        FROM CourseOfferingSchedule
        WHERE CourseOfferingId = :copy.Id
      ];
      Assert.areEqual(
        Date.today().addDays(30),
        pattern.StartDate,
        'Pattern shifted'
      );
      Assert.isTrue(pattern.IsMonday, 'Same weekday');
      Assert.areEqual(Time.newInstance(16, 0, 0, 0), pattern.StartTime, 'Time');
      Assert.isTrue(
        String.join(result.notes, ' ').contains('Assign teachers'),
        'Tells the user to assign teachers'
      );
    }
  }

  @IsTest
  static void cloneWithoutOptionalPartsAndDuplicateDiscount() {
    System.runAs(TestDataFactory.admin()) {
      Template t = template();
      insert new Discount__c(
        Name = 'Taken',
        Code__c = 'SIB10-WFD-02',
        Discount_Type__c = 'Fixed Amount',
        Value__c = 100
      );
      BranchTemplateService.CloneRequest r = request(t.branch.Id, 'WFD-02');
      r.includeRooms = false;
      r.includePrices = false;
      r.includeClosures = false;
      Test.startTest();
      BranchTemplateService.CloneResult result = BranchTemplateService.cloneBranch(
        r
      );
      Test.stopTest();
      Assert.areEqual(0, result.rooms, 'No rooms');
      Assert.areEqual(0, result.prices, 'No prices');
      Assert.areEqual(0, result.discounts, 'Existing code skipped');
      Assert.areEqual(1, result.classes, 'Classes');
      String notes = String.join(result.notes, ' ');
      Assert.isTrue(notes.contains('already exists'), notes);
      Assert.isTrue(notes.contains('no default room'), notes);
      Assert.isNull(
        [SELECT Room__c FROM CourseOffering WHERE Branch__c = :result.branchId]
        .Room__c,
        'No room without copied rooms'
      );
    }
  }

  @IsTest
  static void cloneValidatesRequest() {
    System.runAs(TestDataFactory.admin()) {
      Template t = template();
      Map<String, BranchTemplateService.CloneRequest> cases = new Map<String, BranchTemplateService.CloneRequest>();
      cases.put('template', new BranchTemplateService.CloneRequest());
      BranchTemplateService.CloneRequest noName = request(t.branch.Id, 'X-1');
      noName.name = ' ';
      cases.put('branch name', noName);
      BranchTemplateService.CloneRequest noCode = request(t.branch.Id, '');
      cases.put('branch code', noCode);
      BranchTemplateService.CloneRequest noPrefix = request(t.branch.Id, 'X-2');
      noPrefix.invoicePrefix = '';
      cases.put('invoice prefix', noPrefix);
      cases.put('already used', request(t.branch.Id, t.branch.Branch_Code__c));
      BranchTemplateService.CloneRequest samePrefix = request(
        t.branch.Id,
        'X-3'
      );
      samePrefix.invoicePrefix = 'tst';
      cases.put('prefix TST', samePrefix);
      BranchTemplateService.CloneRequest noStart = request(t.branch.Id, 'X-4');
      noStart.classStartDate = null;
      cases.put('classes start', noStart);
      Test.startTest();
      for (String expected : cases.keySet()) {
        try {
          BranchController.cloneBranch(cases.get(expected));
          Assert.fail('Expected a failure for ' + expected);
        } catch (AuraHandledException e) {
          Assert.isTrue(
            e.getMessage().containsIgnoreCase(expected),
            expected + ': ' + e.getMessage()
          );
        }
      }
      Test.stopTest();
      Assert.areEqual(1, [SELECT COUNT() FROM Branch__c], 'Nothing created');
    }
  }

  @IsTest
  static void previewOfUnknownBranchFails() {
    System.runAs(TestDataFactory.admin()) {
      try {
        BranchController.getTemplatePreview(null);
        Assert.fail('Unknown template');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('not found'), e.getMessage());
      }
    }
  }

  @IsTest
  static void managersCannotOpenBranches() {
    Branch__c branch = TestDataFactory.createBranch();
    User manager = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Branch_Manager')
    );
    System.runAs(manager) {
      try {
        BranchController.cloneBranch(request(branch.Id, 'MGR-1'));
        Assert.fail('Branch managers cannot open branches');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('permission'), e.getMessage());
      }
      Assert.isFalse(
        BranchTemplateService.preview(branch.Id).canCreate,
        'Preview says so'
      );
    }
  }

  @IsTest
  static void overviewComparesBranches() {
    System.runAs(TestDataFactory.admin()) {
      Template t = template();
      Branch__c empty = TestDataFactory.buildBranch();
      empty.Invoice_Prefix__c = 'EMP';
      insert empty;
      update new CourseOffering(
        Id = t.offering.Id,
        Class_Status__c = 'Open',
        EnrollmentCapacity = 10
      );
      Lead enquiry = TestDataFactory.buildEnquiry(t.branch.Id);
      insert enquiry;
      Test.startTest();
      BranchTemplateService.Overview o = BranchController.getOverview();
      Test.stopTest();
      Assert.areEqual(2, o.branches.size(), 'Both branches');
      Assert.isTrue(o.canCreateBranch, 'Admin can create');
      Assert.isTrue(o.showFinance, 'Admin sees finance');
      BranchTemplateService.BranchKpi kpi;
      for (BranchTemplateService.BranchKpi k : o.branches) {
        if (k.branchId == t.branch.Id) {
          kpi = k;
        }
      }
      Assert.areEqual(1, kpi.rooms, 'Rooms');
      Assert.areEqual(1, kpi.activeClasses, 'Active classes');
      Assert.areEqual(10, kpi.capacity, 'Capacity');
      Assert.areEqual(0, kpi.fillRate, 'Nobody enrolled');
      Assert.areEqual(1, kpi.openEnquiries, 'Open enquiry');
      Assert.areEqual(1, o.totals.rooms, 'Totals');
      Assert.areEqual(1, o.totals.openEnquiries, 'Totals enquiries');
      Assert.areEqual('All branches', o.totals.name, 'Totals label');
    }
  }

  @IsTest
  static void classNamesGetTheNewBranch() {
    Branch__c source = new Branch__c(
      Name = 'Indiranagar',
      Branch_Code__c = 'IND'
    );
    Branch__c target = new Branch__c(
      Name = 'Whitefield',
      Branch_Code__c = 'WFD'
    );
    Assert.areEqual(
      'Maths Whitefield',
      BranchTemplateService.className('Maths Indiranagar', source, target),
      'Name'
    );
    Assert.areEqual(
      'Maths WFD A',
      BranchTemplateService.className('Maths IND A', source, target),
      'Code'
    );
    Assert.areEqual(
      'Maths · WFD',
      BranchTemplateService.className('Maths', source, target),
      'Suffix'
    );
  }
}
