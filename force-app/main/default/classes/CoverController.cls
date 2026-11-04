/** Lightning controller for the cover desk: absences, cover teachers and room swaps. */
public with sharing class CoverController {
  @AuraEnabled
  public static CoverService.CoverDesk getDesk() {
    try {
      return CoverService.desk();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id recordAbsence(CoverService.AbsenceRequest request) {
    try {
      return CoverService.recordAbsence(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void withdrawAbsence(Id absenceId) {
    try {
      CoverService.withdrawAbsence(absenceId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<CoverService.Candidate> getCandidates(Id sessionId) {
    try {
      return CoverService.candidates(sessionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void assignCover(Id sessionId, Id coverUserId, String note) {
    try {
      CoverService.assignCover(sessionId, coverUserId, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void cancelForAbsence(Id sessionId, String reason) {
    try {
      CoverService.cancelForAbsence(sessionId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<CoverService.RoomOption> getRoomOptions(Id sessionId) {
    try {
      return CoverService.roomOptions(sessionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void swapRoom(Id sessionId, Id roomId, String note) {
    try {
      CoverService.swapRoom(sessionId, roomId, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
