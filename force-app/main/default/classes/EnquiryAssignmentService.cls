/**
 * Assigns new enquiries to the admissions counsellor of the enquiry's branch
 * with the fewest open enquiries. Counsellors are active Branch_Staff__c
 * assignments with the role "Admissions Counsellor" for active users. Falls
 * back to the branch manager, then leaves the owner unchanged.
 *
 * Workload counting is a system operation (counsellors may not see each
 * other's enquiries), so the queries run without sharing in system mode.
 */
public with sharing class EnquiryAssignmentService {
  public static final String COUNSELLOR_ROLE = 'Admissions Counsellor';
  private static final Set<String> CLOSED_STATUSES = new Set<String>{
    'Unqualified',
    'Qualified'
  };

  public static void assign(List<Lead> enquiries) {
    Set<Id> branchIds = new Set<Id>();
    for (Lead enquiry : enquiries) {
      if (enquiry.Branch__c != null) {
        branchIds.add(enquiry.Branch__c);
      }
    }
    if (branchIds.isEmpty()) {
      return;
    }
    Workload workload = new Workload(branchIds);
    for (Lead enquiry : enquiries) {
      if (
        enquiry.Branch__c == null ||
        workload.isCounsellor(enquiry.OwnerId, enquiry.Branch__c)
      ) {
        continue;
      }
      Id counsellor = workload.nextCounsellor(enquiry.Branch__c);
      Id manager = workload.managerOf(enquiry.Branch__c);
      if (counsellor != null) {
        enquiry.OwnerId = counsellor;
      } else if (manager != null) {
        enquiry.OwnerId = manager;
      }
    }
  }

  private without sharing class Workload {
    private final Map<Id, List<Id>> counsellorsByBranch = new Map<Id, List<Id>>();
    private final Map<Id, Id> managerByBranch = new Map<Id, Id>();
    private final Map<Id, Integer> openCount = new Map<Id, Integer>();

    Workload(Set<Id> branchIds) {
      for (Branch__c branch : [
        SELECT Id, Branch_Manager__c, Branch_Manager__r.IsActive
        FROM Branch__c
        WHERE Id IN :branchIds
        WITH SYSTEM_MODE
      ]) {
        if (
          branch.Branch_Manager__c != null && branch.Branch_Manager__r.IsActive
        ) {
          managerByBranch.put(branch.Id, branch.Branch_Manager__c);
        }
      }
      for (Branch_Staff__c staff : [
        SELECT Branch__c, User__c
        FROM Branch_Staff__c
        WHERE
          Branch__c IN :branchIds
          AND Role__c = :COUNSELLOR_ROLE
          AND Active__c = TRUE
          AND User__r.IsActive = TRUE
        WITH SYSTEM_MODE
        ORDER BY User__c
      ]) {
        if (!counsellorsByBranch.containsKey(staff.Branch__c)) {
          counsellorsByBranch.put(staff.Branch__c, new List<Id>());
        }
        counsellorsByBranch.get(staff.Branch__c).add(staff.User__c);
        openCount.put(staff.User__c, 0);
      }
      if (openCount.isEmpty()) {
        return;
      }
      for (AggregateResult row : [
        SELECT OwnerId owner, COUNT(Id) total
        FROM Lead
        WHERE
          OwnerId IN :openCount.keySet()
          AND IsConverted = FALSE
          AND Status NOT IN :CLOSED_STATUSES
        WITH SYSTEM_MODE
        GROUP BY OwnerId
      ]) {
        openCount.put((Id) row.get('owner'), (Integer) row.get('total'));
      }
    }

    Boolean isCounsellor(Id userId, Id branchId) {
      List<Id> counsellors = counsellorsByBranch.get(branchId);
      return counsellors != null && counsellors.contains(userId);
    }

    Id managerOf(Id branchId) {
      return managerByBranch.get(branchId);
    }

    Id nextCounsellor(Id branchId) {
      List<Id> counsellors = counsellorsByBranch.get(branchId);
      if (counsellors == null || counsellors.isEmpty()) {
        return null;
      }
      Id best;
      for (Id candidate : counsellors) {
        if (best == null || openCount.get(candidate) < openCount.get(best)) {
          best = candidate;
        }
      }
      openCount.put(best, openCount.get(best) + 1);
      return best;
    }
  }
}
