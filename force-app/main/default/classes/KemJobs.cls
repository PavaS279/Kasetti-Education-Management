/**
 * Registry of scheduled jobs for Kasetti Education Management. scheduleAll()
 * is idempotent; scripts/deploy.sh unschedules KEM jobs before a deployment
 * (production blocks deploying classes that scheduled jobs depend on) and calls
 * scheduleAll() afterwards.
 */
public with sharing class KemJobs {
  public static final String PREFIX = 'KEM ';

  @TestVisible
  private static final Map<String, String> CRON = new Map<String, String>{
    'KEM Offer Expiry' => '0 30 1 * * ?'
  };

  public static Integer scheduleAll() {
    Set<String> existing = new Set<String>();
    for (CronTrigger job : [
      SELECT CronJobDetail.Name
      FROM CronTrigger
      WHERE CronJobDetail.Name LIKE 'KEM %'
    ]) {
      existing.add(job.CronJobDetail.Name);
    }
    Integer scheduled = 0;
    for (String name : CRON.keySet()) {
      if (!existing.contains(name)) {
        System.schedule(name, CRON.get(name), jobFor(name));
        scheduled++;
      }
    }
    return scheduled;
  }

  @TestVisible
  private static Schedulable jobFor(String name) {
    switch on name {
      when 'KEM Offer Expiry' {
        return new OfferExpiryJob();
      }
      when else {
        throw new AppException('Unknown job: ' + name);
      }
    }
  }
}
