/** Lightning controller for Give portal access. */
public with sharing class PortalAccessController {
  @AuraEnabled
  public static PortalAccessService.Family getFamily(Id accountId) {
    try {
      return PortalAccessService.family(accountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Boolean prepareAccess(Id accountId) {
    try {
      return PortalAccessService.prepare(accountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PortalAccessService.GiveResult giveAccess(Id accountId) {
    try {
      return PortalAccessService.give(accountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
