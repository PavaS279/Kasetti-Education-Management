@IsTest
private class AppSettingsTest {
  @IsTest
  static void typedAccessorsUseOverridesAndDefaults() {
    AppSettings.overrides.put('Number_Key', '12.5');
    AppSettings.overrides.put('Bool_Key', 'true');
    AppSettings.overrides.put('Bad_Number', 'abc');
    Assert.areEqual(
      12.5,
      AppSettings.getDecimal('Number_Key', 0),
      'Decimal override'
    );
    Assert.areEqual(
      12,
      AppSettings.getInteger('Number_Key', 0),
      'Integer override'
    );
    Assert.isTrue(
      AppSettings.getBoolean('Bool_Key', false),
      'Boolean override'
    );
    Assert.areEqual(
      7,
      AppSettings.getDecimal('Bad_Number', 7),
      'Invalid number falls back to default'
    );
    Assert.areEqual(
      'fallback',
      AppSettings.getString('Missing_Key_XYZ', 'fallback'),
      'Missing key falls back'
    );
    Assert.areEqual(
      3,
      AppSettings.getInteger('Missing_Key_XYZ', 3),
      'Missing integer falls back'
    );
    Assert.isFalse(
      AppSettings.getBoolean('Missing_Key_XYZ', false),
      'Missing boolean falls back'
    );
  }

  @IsTest
  static void branchPolicyPrefersBranchValues() {
    Branch__c branch = TestDataFactory.buildBranch();
    BranchPolicy policy = new BranchPolicy(branch);
    Assert.areEqual(10, policy.invoiceDueDays(), 'Branch due days');
    Assert.areEqual(0.18, policy.taxRate(), 'Branch tax rate as fraction');
    Assert.areEqual(
      0.8,
      policy.attendanceThreshold(),
      'Branch threshold as fraction'
    );
    Assert.areEqual('TST', policy.invoicePrefix(), 'Branch invoice prefix');
  }

  @IsTest
  static void branchPolicyFallsBackToSettings() {
    AppSettings.overrides.put('Default_Invoice_Due_Days', '21');
    AppSettings.overrides.put('Default_Tax_Rate', '0.05');
    AppSettings.overrides.put('Default_Attendance_Threshold', '0.6');
    BranchPolicy policy = new BranchPolicy(null);
    Assert.areEqual(21, policy.invoiceDueDays(), 'Default due days');
    Assert.areEqual(0.05, policy.taxRate(), 'Default tax rate');
    Assert.areEqual(0.6, policy.attendanceThreshold(), 'Default threshold');
    Assert.areEqual('INV', policy.invoicePrefix(), 'Default invoice prefix');
  }
}
