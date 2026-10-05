/**
 * Daily payment reminders as a batch, so any number of invoices due on the
 * reminder dates is covered (due soon, and each overdue reminder day).
 * Delivers the queued email when it finishes.
 * Started by MessageJob ('KEM Payment Reminders', daily 09:05) and from the
 * operations console.
 */
public with sharing class ReminderJob implements Database.Batchable<SObject>, Database.Stateful {
  public static final Integer BATCH_SIZE = 200;
  private final Date today;
  @TestVisible
  private Integer created = 0;

  public ReminderJob(Date today) {
    this.today = today;
  }

  public static Id run(Date today) {
    return Database.executeBatch(new ReminderJob(today), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    Set<Date> dueDates = MessageService.reminderDueDates(today);
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Student_Invoice__c
        WHERE
          Status__c IN :BillingService.OPEN_STATUSES
          AND Due_Date__c IN :dueDates
          AND Balance_Due__c > 0
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<Student_Invoice__c> scope
  ) {
    try {
      created += MessageService.remindInvoices(
        new Map<Id, Student_Invoice__c>(scope).keySet(),
        today
      );
    } catch (Exception e) {
      Logger.error('ReminderJob', e, null);
    }
    Logger.flush();
  }

  public void finish(Database.BatchableContext context) {
    Logger.info(
      'ReminderJob',
      'Payment reminders for ' + today.format() + ': ' + created + ' messages.'
    );
    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new MessageService.DispatchJob());
    }
    Logger.flush();
  }
}
