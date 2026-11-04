/** Lightning controller for the discount list and form. */
public with sharing class DiscountSetupController {
  @AuraEnabled
  public static DiscountSetupService.Overview getOverview() {
    try {
      return DiscountSetupService.overview();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id saveDiscount(DiscountSetupService.DiscountRequest request) {
    try {
      return DiscountSetupService.save(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void setActive(Id discountId, Boolean active) {
    try {
      DiscountSetupService.setActive(discountId, active);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
