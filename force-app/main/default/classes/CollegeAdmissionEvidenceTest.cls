@IsTest
private class CollegeAdmissionEvidenceTest {
  @IsTest
  static void acceptsValidVerifiedEvidence() {
    Account student = new Account(Name = 'Evidence Student');
    insert student;
    User verifier = TestDataFactory.admin();
    Database.insert(
      new Academic_Qualification__c(
        Student__c = student.Id,
        Level__c = 'PUC',
        Stream_Group__c = 'Science',
        Percentage__c = 92,
        Completion_Year__c = Date.today().year(),
        Verified__c = true,
        Verified_By__c = verifier.Id,
        Verified_On__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
    Database.insert(
      new Entrance_Score__c(
        Student__c = student.Id,
        Exam__c = 'KCET',
        Exam_Year__c = Date.today().year(),
        Rank__c = 12000,
        Verified__c = true,
        Verified_By__c = verifier.Id,
        Verified_On__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Academic_Qualification__c
        WHERE Student__c = :student.Id
      ]
    );
    System.assertEquals(
      1,
      [SELECT COUNT() FROM Entrance_Score__c WHERE Student__c = :student.Id]
    );
  }
  @IsTest
  static void rejectsInvalidEvidence() {
    Account student = new Account(Name = 'Invalid Evidence');
    insert student;
    assertRejected(
      new Academic_Qualification__c(
        Student__c = student.Id,
        Level__c = 'PUC',
        Percentage__c = 101,
        Completion_Year__c = Date.today().year()
      ),
      'Percentage'
    );
    assertRejected(
      new Entrance_Score__c(
        Student__c = student.Id,
        Exam__c = 'KCET',
        Exam_Year__c = Date.today().year(),
        Rank__c = 0
      ),
      'Rank'
    );
    assertRejected(
      new Entrance_Score__c(
        Student__c = student.Id,
        Exam__c = 'KCET',
        Exam_Year__c = Date.today().year()
      ),
      'rank or score'
    );
  }
  private static void assertRejected(SObject value, String expected) {
    Database.SaveResult result = Database.insert(
      value,
      false,
      AccessLevel.SYSTEM_MODE
    );
    System.assertEquals(false, result.isSuccess());
    System.assert(
      result.getErrors()[0]
        .getMessage()
        .toLowerCase()
        .contains(expected.toLowerCase()),
      result.getErrors()[0].getMessage()
    );
  }
}
