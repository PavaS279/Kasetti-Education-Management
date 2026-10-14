@IsTest
private class AdmissionDocumentRuleTest {
  @IsTest
  static void stampsUniqueScopeAndValidatesRetention() {
    User admin = TestDataFactory.admin();
    System.runAs(admin) {
      Admission_Document_Rule__c first = rule('Birth Certificate');
      insert first;
      first = [
        SELECT Unique_Key__c
        FROM Admission_Document_Rule__c
        WHERE Id = :first.Id
      ];
      System.assert(first.Unique_Key__c.endsWith('|birth certificate'));
      Database.SaveResult duplicate = Database.insert(
        rule(' Birth Certificate '),
        false
      );
      System.assertEquals(false, duplicate.isSuccess());
      Admission_Document_Rule__c invalid = rule('Address Proof');
      invalid.Retention_Days__c = null;
      Database.SaveResult rejected = Database.insert(invalid, false);
      System.assertEquals(false, rejected.isSuccess());
    }
  }
  private static Admission_Document_Rule__c rule(String type) {
    return new Admission_Document_Rule__c(
      Academic_Year__c = '2026-27',
      Document_Type__c = type,
      Label__c = type,
      Required__c = true,
      Sensitive_Class__c = 'Academic',
      Retain_File__c = true,
      Retention_Days__c = 365,
      Active__c = true
    );
  }
}
