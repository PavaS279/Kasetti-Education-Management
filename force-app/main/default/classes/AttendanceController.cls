/** Lightning controller for the attendance register. */
public with sharing class AttendanceController {
  @AuraEnabled
  public static AttendanceService.Register getRegister(Id sessionId) {
    try {
      return AttendanceService.getRegister(sessionId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void saveRegister(
    Id sessionId,
    List<AttendanceService.RegisterRow> rows,
    String teacherAttendance
  ) {
    try {
      AttendanceService.saveRegister(sessionId, rows, teacherAttendance);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
