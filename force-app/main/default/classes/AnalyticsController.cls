/** Lightning controller for the analytics dashboard. */
public with sharing class AnalyticsController {
  @AuraEnabled
  public static AnalyticsService.Dashboard getDashboard(
    Id branchId,
    Integer months
  ) {
    try {
      return AnalyticsService.dashboard(branchId, months);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<FinanceExportController.BranchOption> getBranches() {
    try {
      List<FinanceExportController.BranchOption> options = new List<FinanceExportController.BranchOption>();
      for (Branch__c branch : [
        SELECT Id, Name
        FROM Branch__c
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        FinanceExportController.BranchOption option = new FinanceExportController.BranchOption();
        option.label = branch.Name;
        option.value = branch.Id;
        options.add(option);
      }
      return options;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
