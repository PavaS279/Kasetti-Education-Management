/**
 * "Add staff member" (Phase 5 stage 2), for administrators holding the
 * KEM Manage Staff custom permission.
 *
 * Creating a login is two steps because Salesforce does not allow users
 * (setup records) and branch roles (data records) in one transaction:
 *   1. createLogin: the user (EDC Staff User profile), the Education Cloud
 *      licence, the persona permission set group and optionally KEM AI User;
 *      the welcome email with the password link is sent if asked.
 *   2. assignRoles: the branch roles (Branch_Staff__c), which give the person
 *      their branches' desks and records.
 * Free licences are checked first. Roles can later be added or ended.
 */
public with sharing class StaffSetupService {
  public static final String MANAGE_STAFF = 'KEM_Manage_Staff';
  @TestVisible
  private static final String PROFILE_NAME = 'EDC Staff User';
  private static final String EDU_LICENCE = 'EducationCloudAccessPsl';
  private static final String EDU_PERMISSION_SET = 'EducationCloudAccess';
  private static final String AI_PERMISSION_SET = 'KEM_AI_User';
  @TestVisible
  private static Integer freeLicencesOverride;

  /** Persona (permission set group) → label and the branch role it usually holds. */
  public static final Map<String, List<String>> PERSONAS = new Map<String, List<String>>{
    'KEM_Teacher_Persona' => new List<String>{ 'Teacher', 'Teacher' },
    'KEM_Academic_Coordinator_Persona' => new List<String>{
      'Academic coordinator',
      'Academic Coordinator'
    },
    'KEM_Admissions_Counsellor_Persona' => new List<String>{
      'Admissions counsellor',
      'Admissions Counsellor'
    },
    'KEM_Finance_Persona' => new List<String>{ 'Finance', 'Finance' },
    'KEM_Branch_Manager_Persona' => new List<String>{
      'Branch manager',
      'Branch Manager'
    },
    'KEM_Administrator_Persona' => new List<String>{ 'Administrator', null }
  };

  /**
   * KEM Manage Staff, plus Salesforce's own Manage Users permission (held by
   * System Administrators): creating logins and assigning licences needs both.
   */
  public static Boolean canManage() {
    return FeatureManagement.checkPermission(MANAGE_STAFF) &&
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND PermissionSet.PermissionsManageUsers = TRUE
        WITH SYSTEM_MODE
      ] > 0;
  }

  private static void requireManage() {
    if (!canManage()) {
      throw new AppException(
        'You do not have access to add staff: it needs the KEM Manage Staff permission and Salesforce\'s Manage Users permission (System Administrators).'
      );
    }
  }

  // --------------------------------------------------------------- overview

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String detail;
    Option(String label, String value, String detail) {
      this.label = label;
      this.value = value;
      this.detail = detail;
    }
  }

  public class RoleRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String role;
  }

  public class StaffRow {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String persona;
    @AuraEnabled
    public Boolean active;
    @AuraEnabled
    public Datetime lastLogin;
    @AuraEnabled
    public List<RoleRow> roles = new List<RoleRow>();
  }

  public class Overview {
    @AuraEnabled
    public Integer freeUserLicences;
    @AuraEnabled
    public Integer freeEducationLicences;
    @AuraEnabled
    public List<Option> personas = new List<Option>();
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<String> roles = new List<String>();
    @AuraEnabled
    public List<StaffRow> staff = new List<StaffRow>();
    @AuraEnabled
    public String usernameSuffix;
  }

  public static Overview overview() {
    requireManage();
    Overview o = new Overview();
    o.freeUserLicences = freeUserLicences();
    o.freeEducationLicences = freeEducationLicences();
    for (String key : PERSONAS.keySet()) {
      o.personas.add(
        new Option(PERSONAS.get(key)[0], key, PERSONAS.get(key)[1])
      );
    }
    for (Branch__c b : [
      SELECT Id, Name
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      o.branches.add(new Option(b.Name, b.Id, null));
    }
    for (
      Schema.PicklistEntry e : Branch_Staff__c.Role__c.getDescribe()
        .getPicklistValues()
    ) {
      if (e.isActive()) {
        o.roles.add(e.getValue());
      }
    }
    o.usernameSuffix = usernameSuffix();

    Map<Id, StaffRow> byUser = new Map<Id, StaffRow>();
    for (PermissionSetAssignment a : [
      SELECT
        AssigneeId,
        Assignee.Name,
        Assignee.Email,
        Assignee.IsActive,
        Assignee.LastLoginDate,
        PermissionSetGroup.DeveloperName
      FROM PermissionSetAssignment
      WHERE PermissionSetGroup.DeveloperName IN :PERSONAS.keySet()
      WITH SYSTEM_MODE
      ORDER BY Assignee.Name
      LIMIT 1000
    ]) {
      if (byUser.containsKey(a.AssigneeId)) {
        continue;
      }
      StaffRow row = new StaffRow();
      row.userId = a.AssigneeId;
      row.name = a.Assignee.Name;
      row.email = a.Assignee.Email;
      row.active = a.Assignee.IsActive;
      row.lastLogin = a.Assignee.LastLoginDate;
      row.persona = PERSONAS.get(a.PermissionSetGroup.DeveloperName)[0];
      byUser.put(a.AssigneeId, row);
    }
    for (Branch_Staff__c s : [
      SELECT Id, User__c, Branch__c, Branch__r.Name, Role__c
      FROM Branch_Staff__c
      WHERE User__c IN :byUser.keySet() AND Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY Branch__r.Name, Role__c
    ]) {
      RoleRow r = new RoleRow();
      r.id = s.Id;
      r.branchId = s.Branch__c;
      r.branch = s.Branch__r.Name;
      r.role = s.Role__c;
      byUser.get(s.User__c).roles.add(r);
    }
    o.staff = byUser.values();
    return o;
  }

  /** Free Salesforce user licences (staff logins). */
  public static Integer freeUserLicences() {
    if (freeLicencesOverride != null) {
      return freeLicencesOverride;
    }
    UserLicense l = [
      SELECT TotalLicenses, UsedLicenses
      FROM UserLicense
      WHERE Name = 'Salesforce'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return l.TotalLicenses - l.UsedLicenses;
  }

  /** Free Education Cloud permission set licences. */
  public static Integer freeEducationLicences() {
    if (freeLicencesOverride != null) {
      return freeLicencesOverride;
    }
    List<PermissionSetLicense> l = [
      SELECT TotalLicenses, UsedLicenses
      FROM PermissionSetLicense
      WHERE DeveloperName = :EDU_LICENCE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return l.isEmpty() ? 0 : l[0].TotalLicenses - l[0].UsedLicenses;
  }

  /** ".ktedutech" style suffix so usernames are unique across Salesforce. */
  public static String usernameSuffix() {
    String host = URL.getOrgDomainUrl().getHost().substringBefore('.');
    return '.' + host.substringBefore('--').toLowerCase();
  }

  // ------------------------------------------------------------ add a login

  public class StaffRequest {
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String mobile { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String persona { get; set; }
    @AuraEnabled
    public Boolean aiUser { get; set; }
    @AuraEnabled
    public String username { get; set; }
    @AuraEnabled
    public Boolean sendEmail { get; set; }
  }

  public class RoleLine {
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String role { get; set; }
  }

  /** Step 1: the login, its licence and permissions. Returns the user Id. */
  public static Id createLogin(StaffRequest r) {
    requireManage();
    if (r == null || String.isBlank(r.lastName)) {
      throw new AppException('Enter the last name.');
    }
    String email = r.email == null ? '' : r.email.trim().toLowerCase();
    if (!Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', email)) {
      throw new AppException('Enter a valid work email address.');
    }
    if (String.isBlank(r.persona) || !PERSONAS.containsKey(r.persona)) {
      throw new AppException('Choose what the person does.');
    }
    if (freeUserLicences() < 1) {
      throw new AppException(
        'There are no free Salesforce user licences. Deactivate a former staff member or buy another licence first.'
      );
    }
    if (freeEducationLicences() < 1) {
      throw new AppException(
        'There are no free Education Cloud licences. Deactivate a former staff member or buy another licence first.'
      );
    }
    String username = String.isBlank(r.username)
      ? email + usernameSuffix()
      : r.username.trim().toLowerCase();
    if (!Pattern.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+', username)) {
      throw new AppException(
        'A username looks like an email address, for example meera@ktedutech.com.kt.'
      );
    }
    if (
      [SELECT COUNT() FROM User WHERE Username = :username WITH SYSTEM_MODE] > 0
    ) {
      throw new AppException('The username ' + username + ' is already used.');
    }
    if (
      [
        SELECT COUNT()
        FROM User
        WHERE Email = :email AND IsActive = TRUE AND UserType = 'Standard'
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException(
        'A staff login with ' + email + ' already exists.'
      );
    }
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = :PROFILE_NAME
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String first = String.isBlank(r.firstName) ? '' : r.firstName.trim();
    String last = r.lastName.trim();
    String alias = (first.left(1) + last.replaceAll('[^A-Za-z]', ''))
      .toLowerCase()
      .left(8);
    User u = new User(
      FirstName = String.isBlank(first) ? null : first,
      LastName = last,
      Email = email,
      Username = username,
      Alias = String.isBlank(alias) ? 'staff' : alias,
      CommunityNickname = (email.substringBefore('@') +
        '.' +
        String.valueOf(Crypto.getRandomInteger()).right(4))
        .left(40),
      MobilePhone = String.isBlank(r.mobile) ? null : r.mobile.trim(),
      Title = String.isBlank(r.title) ? PERSONAS.get(r.persona)[0] : r.title,
      ProfileId = profile.Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_IN',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    Database.DMLOptions options = new Database.DMLOptions();
    options.EmailHeader.triggerUserEmail = r.sendEmail == true;
    Database.SaveResult saved = Database.insert(
      u,
      options,
      AccessLevel.SYSTEM_MODE
    );
    if (!saved.isSuccess()) {
      throw new AppException(saved.getErrors()[0].getMessage());
    }

    List<SObject> grants = new List<SObject>();
    for (PermissionSetLicense l : [
      SELECT Id
      FROM PermissionSetLicense
      WHERE DeveloperName = :EDU_LICENCE
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      grants.add(
        new PermissionSetLicenseAssign(
          AssigneeId = u.Id,
          PermissionSetLicenseId = l.Id
        )
      );
    }
    Database.insert(grants, AccessLevel.SYSTEM_MODE);
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSetGroup g : [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName = :r.persona
      WITH SYSTEM_MODE
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = u.Id,
          PermissionSetGroupId = g.Id
        )
      );
    }
    // The standard Education Cloud set (namespace "force"), as existing staff
    // hold; the org also has an unmanaged copy with Fundraising added.
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :EDU_PERMISSION_SET AND NamespacePrefix = 'force'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (r.aiUser == true) {
      sets.addAll(
        [
          SELECT Id
          FROM PermissionSet
          WHERE Name = :AI_PERMISSION_SET AND NamespacePrefix = NULL
          WITH SYSTEM_MODE
          LIMIT 1
        ]
      );
    }
    for (PermissionSet ps : sets) {
      assignments.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    Database.insert(assignments, AccessLevel.SYSTEM_MODE);
    Logger.info(
      'StaffSetupService',
      'Staff login ' + username + ' created as ' + r.persona + '.'
    );
    return u.Id;
  }

  /** Step 2 (separate transaction): the person's branch roles. */
  public static Integer assignRoles(Id userId, List<RoleLine> lines) {
    requireManage();
    if (userId == null) {
      throw new AppException('Choose the staff member.');
    }
    Set<String> existing = new Set<String>();
    for (Branch_Staff__c s : [
      SELECT Branch__c, Role__c, Active__c, Id
      FROM Branch_Staff__c
      WHERE User__c = :userId
      WITH SYSTEM_MODE
    ]) {
      existing.add(s.Branch__c + ':' + s.Role__c);
    }
    List<Branch_Staff__c> rows = new List<Branch_Staff__c>();
    List<Branch_Staff__c> reactivate = new List<Branch_Staff__c>();
    Map<String, Branch_Staff__c> inactive = new Map<String, Branch_Staff__c>();
    for (Branch_Staff__c s : [
      SELECT Id, Branch__c, Role__c
      FROM Branch_Staff__c
      WHERE User__c = :userId AND Active__c = FALSE
      WITH SYSTEM_MODE
    ]) {
      inactive.put(s.Branch__c + ':' + s.Role__c, s);
    }
    Set<String> seen = new Set<String>();
    for (RoleLine l : lines == null ? new List<RoleLine>() : lines) {
      if (l.branchId == null || String.isBlank(l.role)) {
        continue;
      }
      String key = l.branchId + ':' + l.role;
      if (!seen.add(key)) {
        continue;
      }
      if (inactive.containsKey(key)) {
        reactivate.add(
          new Branch_Staff__c(Id = inactive.get(key).Id, Active__c = true)
        );
      } else if (!existing.contains(key)) {
        rows.add(
          new Branch_Staff__c(
            User__c = userId,
            Branch__c = l.branchId,
            Role__c = l.role,
            Active__c = true
          )
        );
      }
    }
    Database.insert(rows, AccessLevel.SYSTEM_MODE);
    Database.update(reactivate, AccessLevel.SYSTEM_MODE);
    return rows.size() + reactivate.size();
  }

  /** Ends a branch role (kept for history, no longer active). */
  public static void endRole(Id branchStaffId) {
    requireManage();
    Database.update(
      new Branch_Staff__c(Id = branchStaffId, Active__c = false),
      AccessLevel.SYSTEM_MODE
    );
  }
}
