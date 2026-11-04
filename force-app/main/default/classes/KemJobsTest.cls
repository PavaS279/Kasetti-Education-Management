@IsTest
private class KemJobsTest {
  @IsTest
  static void schedulesEachJobOnce() {
    Test.startTest();
    Integer first = KemJobs.scheduleAll();
    Integer second = KemJobs.scheduleAll();
    Test.stopTest();
    Assert.areEqual(KemJobs.CRON.size(), first, 'All jobs scheduled');
    Assert.areEqual(0, second, 'Scheduling is idempotent');
    try {
      KemJobs.jobFor('Nope');
      Assert.fail('Unknown job must fail');
    } catch (AppException e) {
      Assert.isTrue(e.getMessage().contains('Unknown job'), e.getMessage());
    }
  }
}
