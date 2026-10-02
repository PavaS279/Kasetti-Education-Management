@IsTest
private class LoggerTest {
  @IsTest
  static void errorIsPersistedThroughPlatformEvent() {
    Branch__c branch = TestDataFactory.createBranch();
    Test.startTest();
    try {
      throw new AppException('Boom');
    } catch (AppException e) {
      Logger.error('LoggerTest.error', e, branch.Id);
    }
    Test.stopTest();
    Test.getEventBus().deliver();
    List<Error_Log__c> logs = [
      SELECT
        Severity__c,
        Source__c,
        Message__c,
        Record_Id__c,
        Exception_Type__c,
        Stack_Trace__c
      FROM Error_Log__c
    ];
    Assert.areEqual(1, logs.size(), 'One log entry expected');
    Assert.areEqual('ERROR', logs[0].Severity__c, 'Severity should be ERROR');
    Assert.areEqual('Boom', logs[0].Message__c, 'Message should be kept');
    Assert.areEqual(
      branch.Id,
      logs[0].Record_Id__c,
      'Record ID should be kept'
    );
    Assert.areEqual(
      'AppException',
      logs[0].Exception_Type__c,
      'Exception type should be kept'
    );
  }

  @IsTest
  static void respectsLogLevelThreshold() {
    AppSettings.overrides.put('Log_Level', 'WARN');
    Test.startTest();
    Logger.debug('LoggerTest', 'debug');
    Logger.info('LoggerTest', 'info');
    Logger.warn('LoggerTest', 'warn', null);
    Logger.flush();
    Test.stopTest();
    Assert.areEqual(
      1,
      Logger.published.size(),
      'Only WARN and above should be published'
    );
    Assert.areEqual(
      'WARN',
      Logger.published[0].Severity__c,
      'Published entry should be the warning'
    );
  }

  @IsTest
  static void logsFailedSaveResults() {
    List<Room__c> invalid = new List<Room__c>{
      new Room__c(Name = 'No branch')
    };
    Test.startTest();
    List<Database.SaveResult> results = Database.insert(invalid, false);
    Logger.errors('LoggerTest.errors', results);
    Logger.error('LoggerTest.message', 'Plain message', null, '{"a":1}');
    Test.stopTest();
    Assert.areEqual(
      2,
      Logger.published.size(),
      'Failed row and message should both be logged'
    );
  }
}
