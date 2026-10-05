/** Lightning controller for branch templates and branch comparison. */
public with sharing class BranchController {
  @AuraEnabled
  public static BranchTemplateService.Preview getTemplatePreview(Id branchId) {
    try {
      return BranchTemplateService.preview(branchId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BranchTemplateService.CloneResult cloneBranch(
    BranchTemplateService.CloneRequest request
  ) {
    try {
      return BranchTemplateService.cloneBranch(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BranchTemplateService.Overview getOverview() {
    try {
      return BranchTemplateService.overview();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
