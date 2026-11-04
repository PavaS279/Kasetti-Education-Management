@IsTest
private class StatusTransitionServiceTest {
  private static void configure() {
    StatusTransitionService.testTransitions = new List<Status_Transition__mdt>{
      new Status_Transition__mdt(
        Object_Name__c = 'Room__c',
        Field_Name__c = 'Room_Type__c',
        From_Status__c = 'Classroom',
        To_Status__c = 'Hall',
        Active__c = true
      ),
      new Status_Transition__mdt(
        Object_Name__c = 'Room__c',
        Field_Name__c = 'Room_Type__c',
        From_Status__c = 'Hall',
        To_Status__c = 'Studio',
        Active__c = false
      )
    };
  }

  @IsTest
  static void allowsDeclaredTransition() {
    configure();
    Id roomId = TestUtil.fakeId(Room__c.SObjectType);
    Room__c oldRoom = new Room__c(Id = roomId, Room_Type__c = 'Classroom');
    Room__c newRoom = new Room__c(Id = roomId, Room_Type__c = 'Hall');
    StatusTransitionService.validate(
      new List<Room__c>{ newRoom },
      new Map<Id, SObject>{ roomId => oldRoom },
      Room__c.Room_Type__c
    );
    Assert.isFalse(
      newRoom.hasErrors(),
      'Declared transition should be allowed'
    );
    Assert.isTrue(
      StatusTransitionService.isAllowed(
        Room__c.SObjectType,
        Room__c.Room_Type__c,
        'Classroom',
        'Hall'
      ),
      'isAllowed true'
    );
  }

  @IsTest
  static void rejectsUndeclaredOrInactiveTransition() {
    configure();
    Id roomId = TestUtil.fakeId(Room__c.SObjectType);
    Room__c oldRoom = new Room__c(Id = roomId, Room_Type__c = 'Hall');
    Room__c newRoom = new Room__c(Id = roomId, Room_Type__c = 'Studio');
    StatusTransitionService.validate(
      new List<Room__c>{ newRoom },
      new Map<Id, SObject>{ roomId => oldRoom },
      Room__c.Room_Type__c
    );
    Assert.isTrue(
      newRoom.hasErrors(),
      'Inactive transition should be rejected'
    );
    Assert.isFalse(
      StatusTransitionService.isAllowed(
        Room__c.SObjectType,
        Room__c.Room_Type__c,
        'Hall',
        'Classroom'
      ),
      'Undeclared transition rejected'
    );
  }

  @IsTest
  static void ignoresInsertsAndUngovernedFields() {
    configure();
    Room__c room = new Room__c(Room_Type__c = 'Studio');
    StatusTransitionService.validate(
      new List<Room__c>{ room },
      null,
      Room__c.Room_Type__c
    );
    Assert.isFalse(room.hasErrors(), 'Inserts are not governed');
    Assert.isTrue(
      StatusTransitionService.isAllowed(
        Room__c.SObjectType,
        Room__c.Name,
        'a',
        'b'
      ),
      'Ungoverned field allowed'
    );
  }

  @IsTest
  static void treatsBlankLegacyValuesAsDefault() {
    configure();
    Id roomId = TestUtil.fakeId(Room__c.SObjectType);
    Room__c oldRoom = new Room__c(Id = roomId);
    Room__c newRoom = new Room__c(Id = roomId, Room_Type__c = 'Hall');
    StatusTransitionService.validate(
      new List<Room__c>{ newRoom },
      new Map<Id, SObject>{ roomId => oldRoom },
      Room__c.Room_Type__c,
      'Classroom'
    );
    Assert.isFalse(
      newRoom.hasErrors(),
      'Blank legacy value treated as Classroom'
    );
    Room__c unchanged = new Room__c(Id = roomId);
    StatusTransitionService.validate(
      new List<Room__c>{ unchanged },
      new Map<Id, SObject>{ roomId => oldRoom },
      Room__c.Room_Type__c,
      'Classroom'
    );
    Assert.isFalse(
      unchanged.hasErrors(),
      'An unchanged blank value is not a transition'
    );
    Room__c strictRoom = new Room__c(Id = roomId, Room_Type__c = 'Hall');
    StatusTransitionService.validate(
      new List<Room__c>{ strictRoom },
      new Map<Id, SObject>{ roomId => oldRoom },
      Room__c.Room_Type__c
    );
    Assert.isTrue(
      strictRoom.hasErrors(),
      'Without a legacy default, blank to Hall is undeclared'
    );
  }
}
