/** Lightning controller for the ERP journal export on the Finance Desk. */
public with sharing class FinanceExportController {
  public class BranchOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  @AuraEnabled
  public static List<BranchOption> getBranches() {
    try {
      List<BranchOption> options = new List<BranchOption>();
      for (Branch__c branch : [
        SELECT Id, Name, Branch_Code__c
        FROM Branch__c
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        BranchOption option = new BranchOption();
        option.label = branch.Name + ' (' + branch.Branch_Code__c + ')';
        option.value = branch.Id;
        options.add(option);
      }
      return options;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static FinanceExportService.Journal preview(
    Date fromDate,
    Date toDate,
    Id branchId
  ) {
    try {
      FinanceExportService.Journal journal = FinanceExportService.journal(
        fromDate,
        toDate,
        branchId
      );
      // The screen shows account totals and the first lines only.
      if (journal.lines.size() > 50) {
        journal.lines = new List<FinanceExportService.JournalLine>(
          journal.lines
        );
        while (journal.lines.size() > 50) {
          journal.lines.remove(journal.lines.size() - 1);
        }
      }
      return journal;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static FinanceExportService.ExportSummary runExport(
    Date fromDate,
    Date toDate,
    Id branchId
  ) {
    try {
      return FinanceExportService.export(fromDate, toDate, branchId, 'Manual');
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<FinanceExportService.ExportSummary> getRecent() {
    try {
      return FinanceExportService.recent(10);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
