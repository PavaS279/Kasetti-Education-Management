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
    'KEM Offer Expiry' => '0 30 1 * * ?',
    'KEM Waitlist Offers' => '0 5 * * * ?',
    'KEM Recurring Billing' => '0 10 2 * * ?',
    'KEM Payment Reminders' => '0 5 9 * * ?',
    'KEM Message Dispatch' => '0 20 * * * ?',
    'KEM Integration Sync' => '0 40 * * * ?',
    'KEM Finance Export' => '0 15 3 * * ?',
    'KEM Retention' => '0 5 4 * * ?',
    'KEM Library' => '0 15 7 * * ?'
  };

  /** Names of all KEM scheduled jobs, sorted. */
  public static List<String> jobNames() {
    List<String> names = new List<String>(CRON.keySet());
    names.sort();
    return names;
  }

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
      when 'KEM Waitlist Offers' {
        return new WaitlistOfferJob();
      }
      when 'KEM Recurring Billing' {
        return new RecurringBillingJob();
      }
      when 'KEM Payment Reminders' {
        return new MessageJob(true);
      }
      when 'KEM Message Dispatch' {
        return new MessageJob(false);
      }
      when 'KEM Integration Sync' {
        return new IntegrationSyncJob();
      }
      when 'KEM Finance Export' {
        return new FinanceExportJob();
      }
      when 'KEM Retention' {
        return new RetentionJob();
      }
      when 'KEM Library' {
        return new LibraryJob();
      }
      when else {
        throw new AppException('Unknown job: ' + name);
      }
    }
  }
}
