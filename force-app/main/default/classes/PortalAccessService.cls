/**
 * "Give portal access" (Phase 5 stage 4): a family portal login for a
 * guardian (or an older learner), created from the staff screens instead of
 * Setup. The welcome email with the link to set a password is sent at once.
 *
 * Who may: holders of the KEM Manage Portal custom permission who also have
 * Salesforce's Manage External Users (ManagePartners) or Manage Users permission.
 * A login needs: a person account with an email, no login yet, a free
 * Customer Community Plus licence, and an account owner with a role (a
 * Salesforce rule for portal users); prepare() fixes the owner first, in its
 * own transaction, because users and data cannot be saved together.
 */
public with sharing class PortalAccessService {
  public static final String MANAGE_PORTAL = 'KEM_Manage_Portal';
  @TestVisible
  private static final String PROFILE_NAME = 'EDC Community User';
  private static final String PORTAL_LICENCE = 'EducationCloudExprcCloudAccessPsl';
  private static final String PORTAL_PERMISSION_SET = 'KEM_Portal_User';
  @TestVisible
  private static Integer freeLicencesOverride;
  /** Learners younger than this get access through their guardians only. */
  public static final Integer MIN_LEARNER_AGE = 13;

  public static Boolean canGive() {
    return FeatureManagement.checkPermission(MANAGE_PORTAL) &&
      [
        SELECT COUNT()
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND (PermissionSet.PermissionsManageUsers = TRUE
          OR PermissionSet.PermissionsManagePartners = TRUE)
        WITH SYSTEM_MODE
      ] > 0;
  }

  private static void requireGive() {
    if (!canGive()) {
      throw new AppException(
        'You do not have access to give portal access: ask an administrator.'
      );
    }
  }

  public static Integer freeLicences() {
    if (freeLicencesOverride != null) {
      return freeLicencesOverride;
    }
    List<UserLicense> l = [
      SELECT TotalLicenses, UsedLicenses
      FROM UserLicense
      WHERE Name = 'Customer Community Plus'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return l.isEmpty() ? 0 : l[0].TotalLicenses - l[0].UsedLicenses;
  }

  /**
   * The owner for new family accounts when the current user has no role
   * (portal logins need a role on the account owner): the earliest active
   * administrator with a role. Null when the current user has a role.
   */
  public static Id portalOwnerId() {
    if (UserInfo.getUserRoleId() != null) {
      return null;
    }
    for (PermissionSetAssignment a : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSetGroup.DeveloperName = 'KEM_Administrator_Persona'
        AND Assignee.IsActive = TRUE
        AND Assignee.UserRoleId != NULL
      WITH SYSTEM_MODE
      ORDER BY Assignee.CreatedDate
      LIMIT 1
    ]) {
      return a.AssigneeId;
    }
    return null;
  }

  // ----------------------------------------------------------------- status

  public class Person {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public Boolean hasLogin = false;
    @AuraEnabled
    public Boolean active = false;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public Datetime lastLogin;
    @AuraEnabled
    public Boolean canGive = false;
    @AuraEnabled
    public String reason;
  }

  public class Family {
    @AuraEnabled
    public List<Person> people = new List<Person>();
    @AuraEnabled
    public Integer freeLicences;
    @AuraEnabled
    public Boolean canGive;
    @AuraEnabled
    public String portalUrl;
  }

  /** The person, their guardians or children, and each one's portal login. */
  public static Family family(Id accountId) {
    Family f = new Family();
    f.canGive = canGive();
    f.freeLicences = freeLicences();
    f.portalUrl = portalUrl();
    Account a = [
      SELECT Id, PersonContactId
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH USER_MODE
    ];
    // Two steps out: the person's guardians or children, then their other
    // children (siblings) or co-guardians.
    Set<Id> contactIds = new Set<Id>{ a.PersonContactId };
    for (Integer hop = 0; hop < 2; hop++) {
      Set<Id> current = new Set<Id>(contactIds);
      for (ContactContactRelation r : [
        SELECT ContactId, RelatedContactId
        FROM ContactContactRelation
        WHERE
          IsActive = TRUE
          AND (ContactId IN :current
          OR RelatedContactId IN :current)
        WITH SYSTEM_MODE
        LIMIT 200
      ]) {
        contactIds.add(r.ContactId);
        contactIds.add(r.RelatedContactId);
      }
    }
    Map<Id, User> logins = new Map<Id, User>();
    for (User u : [
      SELECT ContactId, Username, IsActive, LastLoginDate
      FROM User
      WHERE ContactId IN :contactIds
      WITH SYSTEM_MODE
    ]) {
      logins.put(u.ContactId, u);
    }
    for (Account p : [
      SELECT
        Id,
        Name,
        KEM_Role__c,
        PersonEmail,
        PersonContactId,
        PersonBirthdate
      FROM Account
      WHERE PersonContactId IN :contactIds
      WITH USER_MODE
      ORDER BY KEM_Role__c DESC, Name
    ]) {
      Person row = new Person();
      row.accountId = p.Id;
      row.name = p.Name;
      row.role = p.KEM_Role__c;
      row.email = p.PersonEmail;
      User u = logins.get(p.PersonContactId);
      if (u != null) {
        row.hasLogin = true;
        row.active = u.IsActive;
        row.username = u.Username;
        row.lastLogin = u.LastLoginDate;
      }
      row.reason = blocker(p, u, f.freeLicences);
      row.canGive = f.canGive && row.reason == null;
      f.people.add(row);
    }
    return f;
  }

  private static String blocker(Account p, User existing, Integer free) {
    if (existing != null) {
      return existing.IsActive
        ? 'Has a portal login'
        : 'Login deactivated (reactivate it in Setup → Users)';
    }
    if (
      p.KEM_Role__c == 'Learner' &&
      (p.PersonBirthdate == null ||
      p.PersonBirthdate.addYears(MIN_LEARNER_AGE) > Date.today())
    ) {
      return 'Under ' + MIN_LEARNER_AGE + ': uses a guardian\'s login';
    }
    if (String.isBlank(p.PersonEmail)) {
      return 'Add an email address first';
    }
    if (free < 1) {
      return 'No free portal licences';
    }
    return null;
  }

  // ------------------------------------------------------------------- give

  /** Step 1 (data): makes sure the account owner has a role. Returns true if the owner changed. */
  public static Boolean prepare(Id accountId) {
    requireGive();
    Account a = [
      SELECT Id, OwnerId, Owner.UserRoleId
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
    ];
    if (a.Owner.UserRoleId != null) {
      return false;
    }
    Id owner = null;
    for (PermissionSetAssignment pa : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSetGroup.DeveloperName = 'KEM_Administrator_Persona'
        AND Assignee.IsActive = TRUE
        AND Assignee.UserRoleId != NULL
      WITH SYSTEM_MODE
      ORDER BY Assignee.CreatedDate
      LIMIT 1
    ]) {
      owner = pa.AssigneeId;
    }
    if (owner == null) {
      throw new AppException(
        'Portal logins need the family\'s record owner to have a role, and no administrator has one. Give an administrator a role in Setup → Users.'
      );
    }
    Database.update(
      new Account(Id = a.Id, OwnerId = owner),
      AccessLevel.SYSTEM_MODE
    );
    return true;
  }

  public class GiveResult {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public Boolean emailSent;
  }

  /** Step 2 (setup): the portal login, its licence and permissions; sends the welcome email. */
  public static GiveResult give(Id accountId) {
    requireGive();
    Account p = [
      SELECT
        Id,
        FirstName,
        LastName,
        PersonEmail,
        PersonContactId,
        KEM_Role__c,
        PersonBirthdate,
        Owner.UserRoleId
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH USER_MODE
    ];
    List<User> existing = [
      SELECT Id, IsActive
      FROM User
      WHERE ContactId = :p.PersonContactId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String reason = blocker(
      p,
      existing.isEmpty() ? null : existing[0],
      freeLicences()
    );
    if (reason != null) {
      throw new AppException(reason + '.');
    }
    if (p.Owner.UserRoleId == null) {
      throw new AppException(
        'The family\'s record owner needs a role first; try again.'
      );
    }
    String email = p.PersonEmail.trim().toLowerCase();
    String username = email + StaffSetupService.usernameSuffix() + '.portal';
    Integer n = 1;
    while (
      [SELECT COUNT() FROM User WHERE Username = :username WITH SYSTEM_MODE] > 0
    ) {
      n++;
      username = email + StaffSetupService.usernameSuffix() + '.portal' + n;
    }
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = :PROFILE_NAME
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    String alias = ((p.FirstName == null ? '' : p.FirstName.left(1)) +
      p.LastName.replaceAll('[^A-Za-z]', ''))
      .toLowerCase()
      .left(8);
    User u = new User(
      ContactId = p.PersonContactId,
      FirstName = p.FirstName,
      LastName = p.LastName,
      Email = email,
      Username = username,
      Alias = String.isBlank(alias) ? 'family' : alias,
      CommunityNickname = (email.substringBefore('@') +
        '.' +
        String.valueOf(Crypto.getRandomInteger()).right(4))
        .left(40),
      ProfileId = profile.Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_IN',
      LanguageLocaleKey = 'en_US',
      EmailEncodingKey = 'UTF-8'
    );
    Database.DMLOptions options = new Database.DMLOptions();
    options.EmailHeader.triggerUserEmail = true;
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
      WHERE DeveloperName = :PORTAL_LICENCE
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
    List<PermissionSetAssignment> sets = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PORTAL_PERMISSION_SET AND NamespacePrefix = NULL
      WITH SYSTEM_MODE
      LIMIT 1
    ]) {
      sets.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    Database.insert(sets, AccessLevel.SYSTEM_MODE);
    Logger.info(
      'PortalAccessService',
      'Portal login ' + username + ' created.'
    );
    GiveResult result = new GiveResult();
    result.userId = u.Id;
    result.username = username;
    result.emailSent = true;
    return result;
  }

  /** The family portal address, from settings (Portal_URL) or the org's site domain. */
  public static String portalUrl() {
    String configured = AppSettings.getString('Portal_URL', null);
    if (String.isNotBlank(configured)) {
      return configured;
    }
    String host = URL.getOrgDomainUrl().getHost().substringBefore('.');
    return 'https://' + host + '.my.site.com/s/my-learning';
  }
}
