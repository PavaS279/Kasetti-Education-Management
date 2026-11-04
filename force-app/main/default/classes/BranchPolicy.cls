/**
 * Resolves operational policies for a branch, falling back to organisation
 * defaults in Education_Setting__mdt when the branch does not override them.
 */
public inherited sharing class BranchPolicy {
  private final Branch__c branch;

  public BranchPolicy(Branch__c branch) {
    this.branch = branch == null ? new Branch__c() : branch;
  }

  public Integer invoiceDueDays() {
    return branch.Invoice_Due_Days__c != null
      ? branch.Invoice_Due_Days__c.intValue()
      : AppSettings.getInteger('Default_Invoice_Due_Days', 14);
  }

  /** Attendance threshold as a fraction between 0 and 1. */
  public Decimal attendanceThreshold() {
    return branch.Attendance_Threshold__c != null
      ? branch.Attendance_Threshold__c / 100
      : AppSettings.getDecimal('Default_Attendance_Threshold', 0.75);
  }

  /** Tax rate as a fraction between 0 and 1. */
  public Decimal taxRate() {
    return branch.Tax_Rate__c != null
      ? branch.Tax_Rate__c / 100
      : AppSettings.getDecimal('Default_Tax_Rate', 0);
  }

  public String invoicePrefix() {
    return String.isBlank(branch.Invoice_Prefix__c)
      ? 'INV'
      : branch.Invoice_Prefix__c;
  }
}
