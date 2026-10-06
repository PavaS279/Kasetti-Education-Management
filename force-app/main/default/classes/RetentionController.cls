/** Lightning controller for the retention desk. */
public with sharing class RetentionController {
  @AuraEnabled
  public static RetentionService.Desk getDesk(Id branchId, String level) {
    try {
      return RetentionService.desk(branchId, level);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void recordFollowUp(
    Id enrolmentId,
    String status,
    String note
  ) {
    try {
      RetentionService.recordFollowUp(enrolmentId, status, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer invite(List<Id> enrolmentIds) {
    try {
      return RetentionService.invite(enrolmentIds);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id recalculate() {
    try {
      if (!OpsService.isAdmin()) {
        throw new AppException(
          'Only administrators can recalculate risk scores.'
        );
      }
      return RetentionJob.run();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
