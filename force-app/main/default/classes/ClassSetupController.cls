/** Lightning controller for the class set-up panel (teacher, faculty, room, seats, status). */
public with sharing class ClassSetupController {
  @AuraEnabled
  public static ClassSetupService.Details getDetails(Id classId, Id branchId) {
    try {
      return ClassSetupService.details(classId, branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static ClassSetupService.Propagation saveClass(
    ClassSetupService.SaveRequest request
  ) {
    try {
      return ClassSetupService.save(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
