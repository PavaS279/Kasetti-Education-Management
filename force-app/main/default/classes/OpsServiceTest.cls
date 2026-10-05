@IsTest
private class OpsServiceTest {
  @IsTest
  static void consoleReportsSchedulesErrorsAndQueues() {
    System.runAs(TestDataFactory.admin()) {
      insert new Error_Log__c(
        Severity__c = 'ERROR',
        Source__c = 'RecurringBillingJob',
        Message__c = 'Simulated failure'
      );
      Test.startTest();
      OpsService.Console before = OpsController.getConsole();
      Assert.areEqual(
        KemJobs.jobNames().size(),
        before.schedules.size(),
        'Every job listed'
      );
      Integer missing = 0;
      for (OpsService.Schedule s : before.schedules) {
        missing += s.missing ? 1 : 0;
      }
      if (missing > 0) {
        Assert.areEqual('failing', before.health, 'Missing schedules fail');
      }
      Assert.areEqual(
        missing,
        OpsController.ensureSchedules(),
        'Missing schedules created'
      );
      OpsService.Console after = OpsService.console();
      for (OpsService.Schedule s : after.schedules) {
        Assert.isFalse(s.missing, s.name + ' scheduled');
        Assert.isNotNull(s.nextRun, s.name + ' has a next run');
      }
      Assert.areEqual(1, after.errorsLast24h, 'Logged error counted');
      Assert.areEqual(
        'RecurringBillingJob',
        after.errorSources[0].source,
        'By source'
      );
      Assert.areEqual(1, after.recentErrors.size(), 'Latest errors');
      Assert.areEqual('attention', after.health, 'Errors need attention');
      Map<String, OpsService.Queue> queues = new Map<String, OpsService.Queue>();
      for (OpsService.Queue q : after.queues) {
        queues.put(q.key, q);
      }
      Assert.isTrue(
        queues.containsKey('reconciliation'),
        'Reconciliation queue'
      );
      Assert.isTrue(queues.containsKey('cover'), 'Cover queue');
      Assert.areEqual(0, queues.get('refunds').count, 'No refunds waiting');
      Test.stopTest();
    }
  }

  @IsTest
  static void jobsCanBeRunNow() {
    System.runAs(TestDataFactory.admin()) {
      Test.startTest();
      for (String name : KemJobs.jobNames()) {
        Assert.isNotNull(OpsController.runNow(name), name + ' started');
      }
      try {
        OpsController.runNow('KEM Nothing');
        Assert.fail('Unknown job');
      } catch (AuraHandledException e) {
        Assert.isNotNull(e.getMessage(), 'Reported');
      }
      Test.stopTest();
      Assert.isFalse(
        [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name IN ('RecurringBillingJob', 'OpsService')
          ]
          .isEmpty(),
        'Jobs ran'
      );
    }
  }

  @IsTest
  static void onlyAdministrators() {
    User teacher = TestDataFactory.createUserWithLicense(
      TestDataFactory.persona('KEM_Teacher')
    );
    System.runAs(teacher) {
      Assert.isFalse(OpsService.isAdmin(), 'Teachers are not administrators');
      try {
        OpsService.console();
        Assert.fail('Administrators only');
      } catch (AppException e) {
        Assert.isTrue(
          e.getMessage().contains('administrators'),
          e.getMessage()
        );
      }
      Integer refused = 0;
      for (Integer i = 0; i < 3; i++) {
        try {
          if (i == 0) {
            OpsController.getConsole();
          } else if (i == 1) {
            OpsController.ensureSchedules();
          } else {
            OpsController.runNow('KEM Recurring Billing');
          }
        } catch (AuraHandledException e) {
          refused++;
        }
      }
      Assert.areEqual(3, refused, 'Every console action is refused');
    }
  }
}
