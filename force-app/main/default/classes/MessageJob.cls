/**
 * Scheduled messaging work. 'KEM Payment Reminders' (daily) sends due-soon and
 * overdue reminders and then delivers queued email; 'KEM Message Dispatch'
 * (hourly) delivers email queued where an async job could not be started
 * (for example from recurring billing batches).
 */
public with sharing class MessageJob implements Schedulable {
  private final Boolean reminders;

  public MessageJob(Boolean reminders) {
    this.reminders = reminders;
  }

  public void execute(SchedulableContext context) {
    Integer created = reminders
      ? MessageService.sendReminders(Date.today())
      : 0;
    if (System.isQueueable()) {
      // Started from the operations console ("Run now"): deliver here.
      MessageService.dispatch(100);
    } else {
      System.enqueueJob(new MessageService.DispatchJob());
    }
    if (reminders) {
      Logger.info(
        'MessageJob',
        'Payment reminders for ' +
          Date.today().format() +
          ': ' +
          created +
          ' messages.'
      );
    }
    Logger.flush();
  }
}
