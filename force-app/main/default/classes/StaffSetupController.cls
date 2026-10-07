/** Lightning controller for Add staff member and staff roles (KEM Manage Staff only). */
public with sharing class StaffSetupController {
  @AuraEnabled
  public static StaffSetupService.Overview getOverview() {
    try {
      return StaffSetupService.overview();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id createLogin(StaffSetupService.StaffRequest request) {
    try {
      return StaffSetupService.createLogin(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer assignRoles(
    Id userId,
    List<StaffSetupService.RoleLine> roles
  ) {
    try {
      return StaffSetupService.assignRoles(userId, roles);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void endRole(Id branchStaffId) {
    try {
      StaffSetupService.endRole(branchStaffId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
