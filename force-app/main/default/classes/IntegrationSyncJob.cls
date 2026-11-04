/**
 * Hourly integration work: pushes pending events to the LMS / ERP named
 * credentials when push is switched on, and purges old events.
 * Schedule: KemJobs ('KEM Integration Sync', minute 40 of every hour).
 */
public with sharing class IntegrationSyncJob implements Schedulable {
  public void execute(SchedulableContext context) {
    System.enqueueJob(new IntegrationService.SyncJob());
  }
}
