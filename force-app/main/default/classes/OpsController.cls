/** Lightning controller for the operations console (administrators). */
public with sharing class OpsController {
  @AuraEnabled
  public static OpsService.Console getConsole() {
    try {
      return OpsService.console();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer ensureSchedules() {
    try {
      return OpsService.ensureSchedules();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static AdminGroupService.SyncResult syncAdministrators() {
    try {
      return OpsService.syncAdministrators();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id runNow(String jobName) {
    try {
      return OpsService.runNow(jobName);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
