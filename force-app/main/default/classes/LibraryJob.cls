/**
 * Daily library run: marks overdue loans and reminds families on days 1, 7
 * and 14 overdue. Schedule: KemJobs ('KEM Library', 07:15).
 */
public with sharing class LibraryJob implements Schedulable {
  public void execute(SchedulableContext context) {
    try {
      Integer reminders = LibraryService.processOverdue(Date.today());
      Logger.info(
        'LibraryJob',
        'Library overdue run: ' + reminders + ' reminder message(s).'
      );
    } catch (Exception e) {
      Logger.error('LibraryJob', e, null);
    }
    Logger.flush();
  }
}
