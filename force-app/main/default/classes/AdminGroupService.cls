/**
 * Keeps the public group KEM Administrators in step with the users who hold
 * the KEM Administrator permission set. Sharing rules give this group edit
 * access to every class and enrolment, because the Education Cloud licence
 * does not allow View All or Modify All on those objects.
 *
 * Group membership is setup data: sync() must run in its own transaction
 * (operations console button, or the deployment script).
 */
public without sharing class AdminGroupService {
  public static final String GROUP_NAME = 'KEM_Administrators';
  public static final String PERMISSION_SET = 'KEM_Administrator';

  public class SyncResult {
    @AuraEnabled
    public Integer added = 0;
    @AuraEnabled
    public Integer removed = 0;
  }

  public static Id groupId() {
    List<Group> rows = [
      SELECT Id
      FROM Group
      WHERE DeveloperName = :GROUP_NAME AND Type = 'Regular'
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0].Id;
  }

  public static Set<Id> administrators() {
    Set<Id> ids = new Set<Id>();
    for (PermissionSetAssignment assignment : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE PermissionSet.Name = :PERMISSION_SET AND Assignee.IsActive = TRUE
    ]) {
      ids.add(assignment.AssigneeId);
    }
    return ids;
  }

  private static Map<Id, GroupMember> members(Id groupId) {
    Map<Id, GroupMember> byUser = new Map<Id, GroupMember>();
    for (GroupMember member : [
      SELECT Id, UserOrGroupId
      FROM GroupMember
      WHERE GroupId = :groupId
    ]) {
      if (String.valueOf(member.UserOrGroupId).startsWith('005')) {
        byUser.put(member.UserOrGroupId, member);
      }
    }
    return byUser;
  }

  /** Administrators who are not yet in the group. */
  public static Integer missing() {
    Id groupId = groupId();
    if (groupId == null) {
      return 0;
    }
    Set<Id> admins = administrators();
    admins.removeAll(members(groupId).keySet());
    return admins.size();
  }

  public static SyncResult sync() {
    SyncResult result = new SyncResult();
    Id groupId = groupId();
    if (groupId == null) {
      throw new AppException('The KEM Administrators group is missing.');
    }
    Set<Id> admins = administrators();
    Map<Id, GroupMember> current = members(groupId);
    List<GroupMember> additions = new List<GroupMember>();
    for (Id userId : admins) {
      if (!current.containsKey(userId)) {
        additions.add(
          new GroupMember(GroupId = groupId, UserOrGroupId = userId)
        );
      }
    }
    List<GroupMember> removals = new List<GroupMember>();
    for (Id userId : current.keySet()) {
      if (!admins.contains(userId)) {
        removals.add(current.get(userId));
      }
    }
    insert additions;
    delete removals;
    result.added = additions.size();
    result.removed = removals.size();
    return result;
  }
}
