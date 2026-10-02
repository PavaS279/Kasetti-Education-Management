/**
 * Creates and finds Person Accounts used for learners and guardians.
 */
public with sharing class PersonAccountService {
  public static Id personRecordTypeId() {
    return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('PersonAccount')
      .getRecordTypeId();
  }

  /** Finds a person by email first, then by mobile phone with the same last name. */
  public static Account findPerson(
    String email,
    String phone,
    String lastName
  ) {
    if (String.isNotBlank(email)) {
      List<Account> byEmail = [
        SELECT Id, PersonContactId, Name, KEM_Role__c, Branch__c
        FROM Account
        WHERE IsPersonAccount = TRUE AND PersonEmail = :email
        WITH USER_MODE
        ORDER BY CreatedDate
        LIMIT 1
      ];
      if (!byEmail.isEmpty()) {
        return byEmail[0];
      }
    }
    if (String.isNotBlank(phone) && String.isNotBlank(lastName)) {
      List<Account> byPhone = [
        SELECT Id, PersonContactId, Name, KEM_Role__c, Branch__c
        FROM Account
        WHERE
          IsPersonAccount = TRUE
          AND LastName = :lastName
          AND (PersonMobilePhone = :phone
          OR Phone = :phone)
        WITH USER_MODE
        ORDER BY CreatedDate
        LIMIT 1
      ];
      if (!byPhone.isEmpty()) {
        return byPhone[0];
      }
    }
    return null;
  }

  public static Account buildPerson(
    String firstName,
    String lastName,
    String email,
    String phone,
    Id branchId,
    String role
  ) {
    return new Account(
      RecordTypeId = personRecordTypeId(),
      FirstName = firstName,
      LastName = lastName,
      PersonEmail = email,
      PersonMobilePhone = phone,
      Branch__c = branchId,
      KEM_Role__c = role
    );
  }

  /** Re-queries accounts so PersonContactId is available after insert. */
  public static Map<Id, Account> reload(Set<Id> accountIds) {
    return new Map<Id, Account>(
      [
        SELECT Id, Name, PersonContactId, KEM_Role__c, Branch__c, PersonEmail
        FROM Account
        WHERE Id IN :accountIds
        WITH USER_MODE
      ]
    );
  }

  /** Merges a new role into an existing role value (Learner + Guardian = Learner and Guardian). */
  public static String mergeRole(String existing, String added) {
    if (String.isBlank(existing) || existing == added) {
      return added;
    }
    return 'Learner and Guardian';
  }
}
