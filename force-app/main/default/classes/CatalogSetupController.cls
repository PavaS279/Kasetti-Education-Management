/** Lightning controller for the course, class and faculty set-up screens. */
public with sharing class CatalogSetupController {
  @AuraEnabled
  public static CatalogSetupService.Choices getChoices() {
    try {
      return CatalogSetupService.choices();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CatalogSetupService.BranchChoices getBranchChoices(
    Id branchId
  ) {
    try {
      return CatalogSetupService.branchChoices(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id createCourse(CatalogSetupService.CourseRequest request) {
    try {
      return CatalogSetupService.createCourse(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CatalogSetupService.ClassPreview previewClass(
    CatalogSetupService.ClassRequest request
  ) {
    try {
      return CatalogSetupService.previewClass(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CatalogSetupService.ClassPreview createClass(
    CatalogSetupService.ClassRequest request
  ) {
    try {
      return CatalogSetupService.createClass(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id createFaculty(CatalogSetupService.FacultyRequest request) {
    try {
      return CatalogSetupService.createFaculty(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
