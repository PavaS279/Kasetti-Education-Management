/** Lightning boundary for the Dean's overdue provisional admissions and the College dues view. */
public with sharing class CollegeAdmissionsController {
  @AuraEnabled
  public static List<CollegeProvisionalService.OverdueRow> getOverdue() {
    try {
      // Only the Dean sees the list; others get null and the component stays hidden.
      if (
        !FeatureManagement.checkPermission(
          CollegeProvisionalService.DEAN_PERMISSION
        )
      ) {
        return null;
      }
      return CollegeProvisionalService.overdueList();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void extendPayment(
    Id enrolmentId,
    Date newDueBy,
    String reason
  ) {
    try {
      CollegeProvisionalService.extend(enrolmentId, newDueBy, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void cancelAdmission(Id enrolmentId, String reason) {
    try {
      CollegeProvisionalService.cancel(enrolmentId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CollegeDuesService.Dues getDues() {
    try {
      return CollegeDuesService.dues();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
