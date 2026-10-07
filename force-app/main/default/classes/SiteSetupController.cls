/** Lightning controller for the branch, room and holiday set-up screens. */
public with sharing class SiteSetupController {
  @AuraEnabled
  public static SiteSetupService.Choices getChoices() {
    try {
      return SiteSetupService.choices();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<SiteSetupService.HolidayLine> getSuggestedHolidays(
    Integer year
  ) {
    try {
      return SiteSetupService.suggestedHolidays(year);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static SiteSetupService.BranchResult createBranch(
    SiteSetupService.BranchRequest request
  ) {
    try {
      return SiteSetupService.createBranch(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Integer addRooms(
    Id branchId,
    List<SiteSetupService.RoomLine> rooms
  ) {
    try {
      return SiteSetupService.addRooms(branchId, rooms);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static SiteSetupService.HolidayResult addHolidays(
    List<Id> branchIds,
    List<SiteSetupService.HolidayLine> holidays
  ) {
    try {
      return SiteSetupService.addHolidays(branchIds, holidays);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
