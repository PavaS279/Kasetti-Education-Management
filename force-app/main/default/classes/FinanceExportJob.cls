/**
 * Daily ERP journal export of yesterday (when Education Setting
 * ERP_Daily_Export is On). Schedule: KemJobs ('KEM Finance Export', 03:15).
 */
public with sharing class FinanceExportJob implements Schedulable, Queueable {
  public void execute(SchedulableContext context) {
    System.enqueueJob(new FinanceExportJob());
  }

  public void execute(QueueableContext context) {
    try {
      FinanceExportService.dailyExport();
    } catch (Exception e) {
      Logger.error('FinanceExportJob', e, null);
    }
    Logger.flush();
  }
}
