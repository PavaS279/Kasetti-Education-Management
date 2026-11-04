/** Lightning controller for the branch library desk. */
public with sharing class LibraryController {
  @AuraEnabled
  public static LibraryService.Desk getDesk(Id branchId, String search) {
    try {
      return LibraryService.desk(branchId, search);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<LibraryService.LearnerOption> findLearners(
    Id branchId,
    String search
  ) {
    try {
      return LibraryService.findLearners(branchId, search);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id addItem(Library_Item__c item) {
    try {
      if (
        item == null ||
        String.isBlank(item.Name) ||
        String.isBlank(item.Item_Code__c)
      ) {
        throw new AppException('Enter the title and the item code.');
      }
      item.Item_Code__c = item.Item_Code__c.trim().toUpperCase();
      insert as user item;
      return item.Id;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id issue(Id itemId, Id learnerAccountId) {
    try {
      return LibraryService.issue(itemId, learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void renew(Id loanId) {
    try {
      LibraryService.renew(loanId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Decimal returnLoan(Id loanId, String condition) {
    try {
      return LibraryService.returnLoan(loanId, condition);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Decimal markLost(Id loanId) {
    try {
      return LibraryService.markLost(loanId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void settleFine(Id loanId, String outcome) {
    try {
      LibraryService.settleFine(loanId, outcome);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
