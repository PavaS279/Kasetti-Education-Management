/**
 * Maintains guardian links between person contacts using the Education Cloud
 * ContactContactRelation object and the "Guardian / Child" PartyRoleRelation.
 * Convention: ContactId = guardian, RelatedContactId = learner.
 */
public with sharing class GuardianRelationshipService {
  public static final String GUARDIAN_ROLE = 'Guardian';
  private static Id guardianRoleId;

  public class GuardianLink {
    public Id guardianContactId;
    public Id learnerContactId;
    public String relationship;
    public Boolean isFeePayer = true;
    public Boolean isEmergencyContact = true;
    public Boolean portalAccess = true;
  }

  public static Id guardianRoleRelationId() {
    if (guardianRoleId == null) {
      List<PartyRoleRelation> roles = [
        SELECT Id
        FROM PartyRoleRelation
        WHERE
          RoleName = :GUARDIAN_ROLE
          AND RelationshipObjectName = 'Contact_Contact_Relationship'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (roles.isEmpty()) {
        throw new AppException(
          'The Guardian relationship role is not configured. Ask an administrator to create a Guardian/Child party role relation.'
        );
      }
      guardianRoleId = roles[0].Id;
    }
    return guardianRoleId;
  }

  /** Creates guardian links that do not already exist. Returns all relation IDs for the requested pairs. */
  public static List<ContactContactRelation> link(List<GuardianLink> links) {
    Set<Id> guardians = new Set<Id>();
    Set<Id> learners = new Set<Id>();
    for (GuardianLink l : links) {
      guardians.add(l.guardianContactId);
      learners.add(l.learnerContactId);
    }
    if (!Schema.SObjectType.ContactContactRelation.isAccessible()) {
      throw new AppException(
        'You do not have access to guardian relationships.'
      );
    }
    Id roleId = guardianRoleRelationId();
    Map<String, ContactContactRelation> existing = new Map<String, ContactContactRelation>();
    for (ContactContactRelation rel : [
      SELECT Id, ContactId, RelatedContactId
      FROM ContactContactRelation
      WHERE
        ContactId IN :guardians
        AND RelatedContactId IN :learners
        AND PartyRoleRelationId = :roleId
      // USER_MODE with bind variables fails on this Industries object
      // ("Variable does not exist: tmpVar1"); object access is checked above
      // and record sharing still applies through "with sharing".
      WITH SYSTEM_MODE
    ]) {
      existing.put(rel.ContactId + ':' + rel.RelatedContactId, rel);
    }
    List<ContactContactRelation> toInsert = new List<ContactContactRelation>();
    List<ContactContactRelation> result = new List<ContactContactRelation>();
    for (GuardianLink l : links) {
      String key = l.guardianContactId + ':' + l.learnerContactId;
      if (existing.containsKey(key)) {
        result.add(existing.get(key));
        continue;
      }
      ContactContactRelation rel = new ContactContactRelation(
        ContactId = l.guardianContactId,
        RelatedContactId = l.learnerContactId,
        PartyRoleRelationId = roleId,
        HierarchyType = 'Parent',
        IsActive = true,
        StartDate = Date.today(),
        Guardian_Relationship__c = l.relationship,
        Is_Fee_Payer__c = l.isFeePayer,
        Is_Emergency_Contact__c = l.isEmergencyContact,
        Portal_Access__c = l.portalAccess
      );
      toInsert.add(rel);
      existing.put(key, rel);
      result.add(rel);
    }
    if (!toInsert.isEmpty()) {
      Database.insert(toInsert, AccessLevel.USER_MODE);
    }
    return result;
  }

  /** Returns the learner contact IDs a guardian contact is linked to (active links only). */
  public static Set<Id> learnersOf(Id guardianContactId, Boolean portalOnly) {
    Id roleId = guardianRoleRelationId();
    Set<Id> learnerIds = new Set<Id>();
    for (ContactContactRelation rel : [
      SELECT RelatedContactId, Portal_Access__c
      FROM ContactContactRelation
      WHERE
        ContactId = :guardianContactId
        AND PartyRoleRelationId = :roleId
        AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (!portalOnly || rel.Portal_Access__c) {
        learnerIds.add(rel.RelatedContactId);
      }
    }
    return learnerIds;
  }
}
