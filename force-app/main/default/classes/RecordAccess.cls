/**
 * Record-level access checks used before a service performs a documented
 * system-mode write (for example stamping system-managed fields).
 */
public with sharing class RecordAccess {
  public static void assertEditable(Id recordId) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
    ];
    if (access.isEmpty() || !access[0].HasEditAccess) {
      throw new AppException(
        'You do not have permission to change this record.'
      );
    }
  }

  public static void assertPermission(String customPermission) {
    if (!FeatureManagement.checkPermission(customPermission)) {
      throw new AppException(
        'You do not have permission to perform this action.'
      );
    }
  }
}
