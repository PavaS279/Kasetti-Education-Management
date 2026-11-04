/**
 * Scheduled messaging work. 'KEM Payment Reminders' (daily) starts the
 * reminder batch (ReminderJob), which delivers queued email when it finishes;
 * 'KEM Message Dispatch' (hourly) delivers email queued where an async job
 * could not be started (for example from recurring billing batches).
 */
public with sharing class MessageJob implements Schedulable {
  private final Boolean reminders;

  public MessageJob(Boolean reminders) {
    this.reminders = reminders;
  }

  public void execute(SchedulableContext context) {
    if (reminders) {
      ReminderJob.run(Date.today());
    } else if (System.isQueueable()) {
      // Started inside a queueable: deliver here instead of chaining a job.
      MessageService.dispatch(100);
    } else {
      System.enqueueJob(new MessageService.DispatchJob());
    }
    Logger.flush();
  }
}
