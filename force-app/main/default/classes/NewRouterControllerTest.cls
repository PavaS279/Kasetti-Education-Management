@IsTest
private class NewRouterControllerTest {
  @IsTest
  static void administratorsGetEveryGuidedScreenAndTheChoice() {
    System.runAs(TestDataFactory.admin()) {
      NewRouterController.Context c = NewRouterController.getContext(
        'Branch__c',
        null
      );
      Assert.areEqual('branch', c.wizard, 'Branch wizard');
      Assert.isTrue(
        c.isAdministrator,
        'Administrators may choose the standard form'
      );
      Assert.areEqual(
        'room',
        NewRouterController.getContext('Room__c', null).wizard,
        'Rooms'
      );
      Assert.areEqual(
        'course',
        NewRouterController.getContext('LearningCourse', null).wizard,
        'Courses'
      );
      Assert.areEqual(
        'class',
        NewRouterController.getContext('CourseOffering', null).wizard,
        'Classes'
      );
      Assert.areEqual(
        'Class',
        NewRouterController.getContext('CourseOffering', null).objectLabel,
        'KTEdutech name'
      );
      Assert.areEqual(
        'family',
        NewRouterController.getContext(
            'Account',
            PersonAccountService.personRecordTypeId()
          )
          .wizard,
        'Person accounts are families'
      );
      Schema.RecordTypeInfo business = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get('Business_Account');
      if (business != null) {
        Assert.isNull(
          NewRouterController.getContext('Account', business.getRecordTypeId())
            .wizard,
          'Business accounts keep the standard form'
        );
      }
      Assert.isNull(
        NewRouterController.wizardFor('Lead', null),
        'Other objects keep the standard form'
      );
      try {
        NewRouterController.getContext('Nope__c', null);
        Assert.fail('Unknown object');
      } catch (AuraHandledException e) {
        Assert.isTrue(
          e.getMessage().contains('Unknown object'),
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void staffGetTheScreensTheyCanComplete() {
    User coordinator = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Academic_Coordinator')
    );
    System.runAs(coordinator) {
      NewRouterController.Context c = NewRouterController.getContext(
        'CourseOffering',
        null
      );
      Assert.areEqual(
        'class',
        c.wizard,
        'Coordinators create classes with the wizard'
      );
      Assert.isFalse(c.isAdministrator, 'No standard-form choice');
      Assert.isNull(
        NewRouterController.getContext('Branch__c', null).wizard,
        'Coordinators do not open branches'
      );
    }
    User manager = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Branch_Manager')
    );
    System.runAs(manager) {
      Assert.isNull(
        NewRouterController.getContext('CourseOffering', null).wizard,
        'Branch managers keep the standard class form'
      );
      Assert.areEqual(
        'room',
        NewRouterController.getContext('Room__c', null).wizard,
        'Rooms'
      );
    }
  }
}
