@IsTest
private class SiteSetupTest {
  private static SiteSetupService.RoomLine room(
    String name,
    String type,
    Integer seats
  ) {
    SiteSetupService.RoomLine r = new SiteSetupService.RoomLine();
    r.name = name;
    r.roomType = type;
    r.capacity = seats;
    return r;
  }

  private static SiteSetupService.RoomLine virtualRoom() {
    SiteSetupService.RoomLine r = room('Online Room', 'Virtual', 30);
    r.meetingUrl = 'https://meet.example.com/kt-online';
    return r;
  }

  private static SiteSetupService.HolidayLine holiday(
    String name,
    Date day,
    Date endDay
  ) {
    SiteSetupService.HolidayLine h = new SiteSetupService.HolidayLine();
    h.name = name;
    h.startDate = day;
    h.endDate = endDay;
    return h;
  }

  private static SiteSetupService.BranchRequest branch(
    String name,
    String code,
    String prefix
  ) {
    SiteSetupService.BranchRequest r = new SiteSetupService.BranchRequest();
    r.name = name;
    r.code = code;
    r.invoicePrefix = prefix;
    r.city = 'Bengaluru';
    r.state = 'Karnataka';
    r.deliveryModes = new List<String>{ 'Classroom', 'Online' };
    r.attendanceThreshold = 75;
    r.rooms = new List<SiteSetupService.RoomLine>{
      room('Ramanujan Room', 'Classroom', 12),
      virtualRoom(),
      room('', null, null)
    };
    r.holidays = new List<SiteSetupService.HolidayLine>{
      holiday('Kannada Rajyotsava', Date.newInstance(2026, 11, 1), null),
      holiday(
        'Deepavali break',
        Date.newInstance(2026, 11, 7),
        Date.newInstance(2026, 11, 10)
      )
    };
    return r;
  }

  @IsTest
  static void opensABranchWithRoomsAndHolidays() {
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      SiteSetupService.BranchResult result = SiteSetupController.createBranch(
        branch('KT Edutech Jayanagar', 'jpn-01', 'jpn')
      );
      Test.stopTest();
      Branch__c b = [
        SELECT
          Branch_Code__c,
          Invoice_Prefix__c,
          Country__c,
          Delivery_Modes__c,
          Tax_Rate__c,
          Invoice_Due_Days__c,
          Active__c
        FROM Branch__c
        WHERE Id = :result.branchId
      ];
      Assert.areEqual('JPN-01', b.Branch_Code__c, 'Code upper-cased');
      Assert.areEqual('JPN', b.Invoice_Prefix__c, 'Prefix upper-cased');
      Assert.areEqual('India', b.Country__c, 'Country default');
      Assert.areEqual('Classroom;Online', b.Delivery_Modes__c, 'Modes');
      Assert.areEqual(18, b.Tax_Rate__c, 'GST default');
      Assert.areEqual(10, b.Invoice_Due_Days__c, 'Payment terms default');
      Assert.areEqual(2, result.rooms, 'Blank room line skipped');
      Assert.areEqual(2, result.holidays, 'Holidays');
      Assert.areEqual(
        Date.newInstance(2026, 11, 1),
        [
          SELECT End_Date__c
          FROM Calendar_Closure__c
          WHERE Name = 'Kannada Rajyotsava'
        ]
        .End_Date__c,
        'One-day holiday ends the same day'
      );

      Integer branches = [SELECT COUNT() FROM Branch__c];
      for (
        SiteSetupService.BranchRequest bad : new List<SiteSetupService.BranchRequest>{
          branch('Another', 'JPN-01', 'ANO'),
          branch('Another', 'ANO-01', 'JPN'),
          branch('KT Edutech Jayanagar', 'ANO-01', 'ANO'),
          branch('', 'ANO-01', 'ANO')
        }
      ) {
        try {
          SiteSetupService.createBranch(bad);
          Assert.fail('Expected a refusal');
        } catch (AppException e) {
          Assert.isNotNull(e.getMessage(), 'Explained');
        }
      }
      SiteSetupService.BranchRequest noSeats = branch(
        'Whitefield',
        'WFD-01',
        'WFD'
      );
      noSeats.rooms[0].capacity = null;
      try {
        SiteSetupService.createBranch(noSeats);
        Assert.fail('Room needs seats');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('seats'), e.getMessage());
      }
      SiteSetupService.BranchRequest tax = branch(
        'Whitefield',
        'WFD-01',
        'WFD'
      );
      tax.taxRate = 180;
      try {
        SiteSetupService.createBranch(tax);
        Assert.fail('Tax is a percentage');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('tax rate'), e.getMessage());
      }
      Assert.areEqual(
        branches,
        [SELECT COUNT() FROM Branch__c],
        'Nothing half-saved'
      );
    }
  }

  @IsTest
  static void addsRoomsAndHolidaysToBranches() {
    System.runAs(TestDataFactory.admin()) {
      Branch__c a = TestDataFactory.createBranch();
      Branch__c b = TestDataFactory.createBranch();
      Test.startTest();
      Integer added = SiteSetupController.addRooms(
        a.Id,
        new List<SiteSetupService.RoomLine>{
          room('Turing Lab', 'Laboratory', 10),
          room('Raman Hall', 'Hall', 30)
        }
      );
      Assert.areEqual(2, added, 'Rooms');
      try {
        SiteSetupService.addRooms(
          a.Id,
          new List<SiteSetupService.RoomLine>{
            room('turing lab', 'Laboratory', 8)
          }
        );
        Assert.fail('Duplicate room name');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('already a room'),
          e.getMessage()
        );
      }
      try {
        SiteSetupService.addRooms(
          a.Id,
          new List<SiteSetupService.RoomLine>{ room(' ', null, null) }
        );
        Assert.fail('No names');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('at least one'), e.getMessage());
      }

      List<SiteSetupService.HolidayLine> year = SiteSetupController.getSuggestedHolidays(
        2026
      );
      SiteSetupService.HolidayResult first = SiteSetupController.addHolidays(
        new List<Id>{ a.Id, b.Id },
        year
      );
      SiteSetupService.HolidayResult again = SiteSetupService.addHolidays(
        new List<Id>{ a.Id },
        year
      );
      Test.stopTest();
      Assert.areEqual(
        year.size() * 2,
        first.created,
        'Every holiday at both branches'
      );
      Assert.areEqual(0, again.created, 'Re-applying adds nothing');
      Assert.areEqual(year.size(), again.skipped, 'All skipped');
      try {
        SiteSetupService.addHolidays(
          new List<Id>{ a.Id },
          new List<SiteSetupService.HolidayLine>{
            holiday('Backwards', Date.today(), Date.today().addDays(-1))
          }
        );
        Assert.fail('End before start');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('cannot end before'),
          e.getMessage()
        );
      }
      try {
        SiteSetupService.addHolidays(new List<Id>(), year);
        Assert.fail('Needs a branch');
      } catch (AppException e) {
        Assert.isTrue(e.getMessage().contains('branch'), e.getMessage());
      }
    }
  }

  @IsTest
  static void suggestsTheYearsHolidaysInDateOrder() {
    List<SiteSetupService.HolidayLine> y2026 = SiteSetupService.suggestedHolidays(
      2026
    );
    for (Integer i = 1; i < y2026.size(); i++) {
      Assert.isTrue(y2026[i - 1].startDate <= y2026[i].startDate, 'Sorted');
    }
    Assert.areEqual('Makara Sankranti', y2026[0].name, 'First of the year');
    Assert.isTrue(y2026[0].checkDate, 'Festival date to check');
    Assert.areEqual('Republic Day', y2026[1].name, 'Then Republic Day');
    Assert.isFalse(y2026[1].checkDate, 'Fixed date');
    Boolean festivalFlagged = false;
    for (SiteSetupService.HolidayLine h : y2026) {
      if (h.name == 'Ganesh Chaturthi') {
        festivalFlagged = h.checkDate;
      }
    }
    Assert.isTrue(festivalFlagged, 'Festival dates are marked to check');
    Assert.areEqual(13, y2026.size(), '6 fixed, 6 festivals, Christmas break');
    Assert.areEqual(
      7,
      SiteSetupService.suggestedHolidays(2031).size(),
      'No festival dates known'
    );
  }

  @IsTest
  static void choicesAndAccess() {
    System.runAs(TestDataFactory.admin()) {
      TestDataFactory.createBranch();
      SiteSetupService.Choices c = SiteSetupController.getChoices();
      Assert.areEqual(1, c.branches.size(), 'Branch offered');
      Assert.isTrue(c.canCreateBranch, 'Administrators open branches');
      Assert.isNotNull(c.managers, 'Managers listed');
      Assert.isFalse(c.suggestedHolidays.isEmpty(), 'This year');
    }
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      try {
        SiteSetupController.createBranch(
          branch('Teacher Branch', 'TCH-01', 'TCH')
        );
        Assert.fail('Teachers cannot open branches');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        SiteSetupController.addRooms(null, null);
        Assert.fail('Teachers cannot add rooms');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
      try {
        SiteSetupController.addHolidays(null, null);
        Assert.fail('Teachers cannot add holidays');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('access'), e.getMessage());
      }
    }
  }
}
