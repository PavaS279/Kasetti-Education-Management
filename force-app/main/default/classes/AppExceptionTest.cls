@IsTest
private class AppExceptionTest {
  @IsTest
  static void businessMessagesPassThrough() {
    AuraHandledException aura = AppException.toAura(
      new AppException('Seat limit reached')
    );
    Assert.areEqual(
      'Seat limit reached',
      aura.getMessage(),
      'Business message should be shown'
    );
  }

  @IsTest
  static void unexpectedErrorsAreMasked() {
    AuraHandledException aura = AppException.toAura(new NullPointerException());
    Assert.areEqual(
      System.Label.KEM_Unexpected_Error,
      aura.getMessage(),
      'Internal errors must be masked'
    );
  }

  @IsTest
  static void dmlMessagesAreReadable() {
    try {
      insert new Room__c(Name = 'No branch');
      Assert.fail('Insert should fail');
    } catch (DmlException e) {
      AuraHandledException aura = AppException.toAura(e);
      Assert.isTrue(
        String.isNotBlank(aura.getMessage()),
        'DML message should be shown'
      );
    }
  }
}
