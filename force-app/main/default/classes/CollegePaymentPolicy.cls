/** College payment restrictions shared by service, API, and direct-DML paths. */
public without sharing class CollegePaymentPolicy {
  private static Map<Id, Branch__c> branchCache = new Map<Id, Branch__c>();
  private static final Set<String> CLEARING_METHODS = new Set<String>{
    'Cheque',
    'Demand Draft'
  };

  public static void validate(
    List<Student_Payment__c> payments,
    Boolean isInsert
  ) {
    Set<Id> branchIds = new Set<Id>();
    for (Student_Payment__c payment : payments) {
      if (payment.Branch__c != null)
        branchIds.add(payment.Branch__c);
    }
    Set<Id> missing = branchIds.clone();
    missing.removeAll(branchCache.keySet());
    if (!missing.isEmpty()) {
      branchCache.putAll(
        [
          SELECT Institution_Type__c, Allowed_Payment_Methods__c
          FROM Branch__c
          WHERE Id IN :missing
          WITH SYSTEM_MODE
        ]
      );
    }
    for (Student_Payment__c payment : payments) {
      validateOne(payment, branchCache.get(payment.Branch__c), isInsert);
    }
  }

  private static void validateOne(
    Student_Payment__c payment,
    Branch__c branch,
    Boolean isInsert
  ) {
    if (CLEARING_METHODS.contains(payment.Method__c)) {
      if (
        String.isBlank(payment.Instrument_Number__c) ||
        String.isBlank(payment.Instrument_Bank__c) ||
        payment.Instrument_Date__c == null
      ) {
        payment.addError(
          'Enter the instrument number, bank and date for a cheque or demand draft.'
        );
      }
      if (isInsert && payment.Status__c != 'Pending') {
        payment.addError(
          'Cheques and demand drafts must be recorded as Pending until cleared.'
        );
      }
    }
    if (payment.Method__c == 'Credit Note' && payment.Credit_Note__c == null) {
      payment.addError(
        'Credit Note payments can only be created from an authorised credit note.'
      );
    }
    if (branch?.Institution_Type__c != 'College')
      return;
    Set<String> allowed = new Set<String>();
    if (String.isNotBlank(branch.Allowed_Payment_Methods__c)) {
      allowed.addAll(branch.Allowed_Payment_Methods__c.split(';'));
    }
    if (payment.Method__c == 'Cash' || !allowed.contains(payment.Method__c)) {
      payment.addError(
        'Payment method ' +
          payment.Method__c +
          ' is not allowed at this college campus.'
      );
    }
  }
}
