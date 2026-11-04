/**
 * Learner and guardian record management: learner profiles, guardian links,
 * communication preferences, and the Learner 360 read model.
 */
public with sharing class LearnerService {
  public class GuardianInput {
    @AuraEnabled
    public Id existingAccountId { get; set; }
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String relationship { get; set; }
    @AuraEnabled
    public Boolean isFeePayer { get; set; }
    @AuraEnabled
    public Boolean portalAccess { get; set; }
    @AuraEnabled
    public Boolean isEmergencyContact { get; set; }
  }

  public class PreferenceInput {
    @AuraEnabled
    public String preferredChannel { get; set; }
    @AuraEnabled
    public String preferredLanguage { get; set; }
    @AuraEnabled
    public Boolean smsOptIn { get; set; }
    @AuraEnabled
    public Boolean whatsAppOptIn { get; set; }
    @AuraEnabled
    public Boolean emailOptOut { get; set; }
    @AuraEnabled
    public String emergencyInstructions { get; set; }
  }

  public class PersonLink {
    @AuraEnabled
    public Id relationId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String relationship;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public Boolean isFeePayer;
    @AuraEnabled
    public Boolean portalAccess;
    @AuraEnabled
    public Boolean isEmergencyContact;
  }

  public class Learner360 {
    @AuraEnabled
    public Account person;
    @AuraEnabled
    public LearnerProfile profile;
    @AuraEnabled
    public Boolean isLearner;
    @AuraEnabled
    public Boolean isGuardian;
    @AuraEnabled
    public List<PersonLink> guardians = new List<PersonLink>();
    @AuraEnabled
    public List<PersonLink> children = new List<PersonLink>();
    @AuraEnabled
    public List<PersonLink> siblings = new List<PersonLink>();
    @AuraEnabled
    public List<IndividualApplication> applications = new List<IndividualApplication>();
    @AuraEnabled
    public List<CourseOfferingParticipant> enrolments = new List<CourseOfferingParticipant>();
  }

  public static Boolean isLearner(String role) {
    return role == 'Learner' || role == 'Learner and Guardian';
  }

  public static Boolean isGuardian(String role) {
    return role == 'Guardian' || role == 'Learner and Guardian';
  }

  /**
   * Creates a LearnerProfile for learners that do not have one. The profile is
   * a derived record of the learner, so it is created in system mode for
   * whoever creates the learner (counsellor, integration, conversion).
   */
  public static void ensureProfiles(Set<Id> learnerAccountIds) {
    if (learnerAccountIds == null || learnerAccountIds.isEmpty()) {
      return;
    }
    Map<Id, Account> learners = new Map<Id, Account>(
      [
        SELECT Id, Name, PersonContactId, PersonEmail, Branch__c
        FROM Account
        WHERE Id IN :learnerAccountIds AND IsPersonAccount = TRUE
        WITH SYSTEM_MODE
      ]
    );
    Set<Id> contactIds = new Set<Id>();
    for (Account learner : learners.values()) {
      contactIds.add(learner.PersonContactId);
    }
    Set<Id> withProfile = new Set<Id>();
    for (LearnerProfile profile : [
      SELECT ContactId
      FROM LearnerProfile
      WHERE ContactId IN :contactIds
      WITH SYSTEM_MODE
    ]) {
      withProfile.add(profile.ContactId);
    }
    List<LearnerProfile> profiles = new List<LearnerProfile>();
    for (Account learner : learners.values()) {
      if (!withProfile.contains(learner.PersonContactId)) {
        profiles.add(
          new LearnerProfile(
            Name = learner.Name.left(80),
            ContactId = learner.PersonContactId,
            Email = learner.PersonEmail,
            Branch__c = learner.Branch__c
          )
        );
      }
    }
    if (!profiles.isEmpty()) {
      Logger.errors(
        'LearnerService.ensureProfiles',
        Database.insert(profiles, false, AccessLevel.SYSTEM_MODE)
      );
    }
  }

  public static Learner360 getLearner360(Id accountId) {
    List<Account> people = [
      SELECT
        Id,
        Name,
        FirstName,
        LastName,
        IsPersonAccount,
        PersonContactId,
        PersonEmail,
        PersonMobilePhone,
        Phone,
        PersonBirthdate,
        PersonHasOptedOutOfEmail,
        KEM_Role__c,
        Branch__c,
        Branch__r.Name,
        Preferred_Channel__pc,
        Preferred_Language__pc,
        SMS_Opt_In__pc,
        WhatsApp_Opt_In__pc,
        Emergency_Instructions__pc
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
    ];
    if (people.isEmpty()) {
      throw new AppException('Record not found or not accessible.');
    }
    Learner360 view = new Learner360();
    view.person = people[0];
    view.isLearner = isLearner(view.person.KEM_Role__c);
    view.isGuardian = isGuardian(view.person.KEM_Role__c);
    if (!view.person.IsPersonAccount) {
      return view;
    }
    Id contactId = view.person.PersonContactId;
    List<LearnerProfile> profiles = [
      SELECT
        Id,
        Name,
        Student_Number__c,
        EnrollmentStatus,
        AcademicLevel,
        Branch__r.Name,
        CreatedDate
      FROM LearnerProfile
      WHERE ContactId = :contactId
      WITH USER_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ];
    view.profile = profiles.isEmpty() ? null : profiles[0];

    if (Schema.SObjectType.ContactContactRelation.isAccessible()) {
      view.guardians = guardiansOf(contactId);
      view.children = childrenOf(contactId);
      view.siblings = siblingsOf(contactId, view.guardians);
    }
    view.applications = [
      SELECT
        Id,
        Name,
        Status,
        AppliedDate,
        Learning_Course__r.Name,
        Learning_Program__r.Name,
        Branch__r.Name
      FROM IndividualApplication
      WHERE AccountId = :accountId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];
    view.enrolments = [
      SELECT
        Id,
        Name,
        ParticipationStatus,
        StartDate,
        EndDate,
        CourseOffering.Name,
        CourseOffering.LearningCourse.Name
      FROM CourseOfferingParticipant
      WHERE ParticipantContactId = :contactId
      WITH USER_MODE
      ORDER BY CreatedDate DESC
      LIMIT 50
    ];
    return view;
  }

  /** Links a guardian to a learner, reusing an existing person when one matches. */
  public static Id addGuardian(Id learnerAccountId, GuardianInput input) {
    Savepoint sp = Database.setSavepoint();
    try {
      Account learner = PersonAccountService.reload(
          new Set<Id>{ learnerAccountId }
        )
        .get(learnerAccountId);
      if (learner == null || learner.PersonContactId == null) {
        throw new AppException(
          'Guardians can only be added to a person account learner.'
        );
      }
      Id guardianAccountId = input.existingAccountId;
      if (guardianAccountId == null) {
        if (String.isBlank(input.lastName)) {
          throw new AppException(
            'Enter the guardian\'s last name or choose an existing person.'
          );
        }
        Account match = PersonAccountService.findPerson(
          input.email,
          input.phone,
          input.lastName
        );
        if (match != null) {
          guardianAccountId = match.Id;
        } else {
          Account guardian = PersonAccountService.buildPerson(
            input.firstName,
            input.lastName,
            input.email,
            input.phone,
            learner.Branch__c,
            'Guardian'
          );
          Database.insert(guardian, AccessLevel.USER_MODE);
          guardianAccountId = guardian.Id;
        }
      }
      if (guardianAccountId == learnerAccountId) {
        throw new AppException('A learner cannot be their own guardian.');
      }
      Account guardian = PersonAccountService.reload(
          new Set<Id>{ guardianAccountId }
        )
        .get(guardianAccountId);
      String role = PersonAccountService.mergeRole(
        guardian.KEM_Role__c,
        'Guardian'
      );
      if (role != guardian.KEM_Role__c) {
        Database.update(
          new Account(Id = guardian.Id, KEM_Role__c = role),
          AccessLevel.USER_MODE
        );
      }
      GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
      link.guardianContactId = guardian.PersonContactId;
      link.learnerContactId = learner.PersonContactId;
      link.relationship = input.relationship;
      link.isFeePayer = input.isFeePayer == true;
      link.portalAccess = input.portalAccess == true;
      link.isEmergencyContact = input.isEmergencyContact == true;
      return GuardianRelationshipService.link(
          new List<GuardianRelationshipService.GuardianLink>{ link }
        )[0]
        .Id;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  public static void updateGuardianLink(Id relationId, GuardianInput input) {
    Database.update(
      new ContactContactRelation(
        Id = relationId,
        Guardian_Relationship__c = input.relationship,
        Is_Fee_Payer__c = input.isFeePayer == true,
        Portal_Access__c = input.portalAccess == true,
        Is_Emergency_Contact__c = input.isEmergencyContact == true
      ),
      AccessLevel.USER_MODE
    );
  }

  /** Ends a guardian link (kept for history) and revokes portal access through it. */
  public static void endGuardianLink(Id relationId) {
    Database.update(
      new ContactContactRelation(
        Id = relationId,
        IsActive = false,
        EndDate = Date.today(),
        Portal_Access__c = false,
        Is_Fee_Payer__c = false
      ),
      AccessLevel.USER_MODE
    );
  }

  public static void updatePreferences(Id accountId, PreferenceInput input) {
    Database.update(
      new Account(
        Id = accountId,
        Preferred_Channel__pc = input.preferredChannel,
        Preferred_Language__pc = input.preferredLanguage,
        SMS_Opt_In__pc = input.smsOptIn == true,
        WhatsApp_Opt_In__pc = input.whatsAppOptIn == true,
        PersonHasOptedOutOfEmail = input.emailOptOut == true,
        Emergency_Instructions__pc = input.emergencyInstructions
      ),
      AccessLevel.USER_MODE
    );
  }

  public static List<Account> searchPeople(String term) {
    if (String.isBlank(term) || term.trim().length() < 2) {
      return new List<Account>();
    }
    String pattern = '%' + String.escapeSingleQuotes(term.trim()) + '%';
    return [
      SELECT Id, Name, PersonEmail, PersonMobilePhone, KEM_Role__c
      FROM Account
      WHERE
        IsPersonAccount = TRUE
        AND (Name LIKE :pattern
        OR PersonEmail LIKE :pattern
        OR PersonMobilePhone LIKE :pattern)
      WITH USER_MODE
      ORDER BY Name
      LIMIT 10
    ];
  }

  // ------------------------------------------------------------------ links

  private static List<PersonLink> guardiansOf(Id learnerContactId) {
    Id roleId = GuardianRelationshipService.guardianRoleRelationId();
    List<PersonLink> links = new List<PersonLink>();
    for (ContactContactRelation rel : [
      SELECT
        Id,
        ContactId,
        Contact.AccountId,
        Contact.Name,
        Contact.Email,
        Contact.MobilePhone,
        Guardian_Relationship__c,
        Is_Fee_Payer__c,
        Portal_Access__c,
        Is_Emergency_Contact__c
      FROM ContactContactRelation
      WHERE
        RelatedContactId = :learnerContactId
        AND PartyRoleRelationId = :roleId
        AND IsActive = TRUE
      // See GuardianRelationshipService: USER_MODE + binds fails on this object.
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ]) {
      links.add(toLink(rel, rel.Contact));
    }
    return links;
  }

  private static List<PersonLink> childrenOf(Id guardianContactId) {
    Id roleId = GuardianRelationshipService.guardianRoleRelationId();
    List<PersonLink> links = new List<PersonLink>();
    for (ContactContactRelation rel : [
      SELECT
        Id,
        RelatedContactId,
        RelatedContact.AccountId,
        RelatedContact.Name,
        RelatedContact.Email,
        RelatedContact.MobilePhone,
        Guardian_Relationship__c,
        Is_Fee_Payer__c,
        Portal_Access__c,
        Is_Emergency_Contact__c
      FROM ContactContactRelation
      WHERE
        ContactId = :guardianContactId
        AND PartyRoleRelationId = :roleId
        AND IsActive = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
    ]) {
      links.add(toLink(rel, rel.RelatedContact));
    }
    return links;
  }

  /** Other learners who share at least one active guardian with this learner. */
  private static List<PersonLink> siblingsOf(
    Id learnerContactId,
    List<PersonLink> guardians
  ) {
    Set<Id> guardianAccountIds = new Set<Id>();
    for (PersonLink g : guardians) {
      guardianAccountIds.add(g.accountId);
    }
    if (guardianAccountIds.isEmpty()) {
      return new List<PersonLink>();
    }
    Id roleId = GuardianRelationshipService.guardianRoleRelationId();
    Map<Id, PersonLink> siblings = new Map<Id, PersonLink>();
    for (ContactContactRelation rel : [
      SELECT RelatedContactId, RelatedContact.AccountId, RelatedContact.Name
      FROM ContactContactRelation
      WHERE
        Contact.AccountId IN :guardianAccountIds
        AND RelatedContactId != :learnerContactId
        AND PartyRoleRelationId = :roleId
        AND IsActive = TRUE
      WITH SYSTEM_MODE
    ]) {
      PersonLink sibling = new PersonLink();
      sibling.accountId = rel.RelatedContact.AccountId;
      sibling.name = rel.RelatedContact.Name;
      siblings.put(sibling.accountId, sibling);
    }
    return siblings.values();
  }

  private static PersonLink toLink(ContactContactRelation rel, Contact person) {
    PersonLink link = new PersonLink();
    link.relationId = rel.Id;
    link.accountId = person.AccountId;
    link.name = person.Name;
    link.email = person.Email;
    link.phone = person.MobilePhone;
    link.relationship = rel.Guardian_Relationship__c;
    link.isFeePayer = rel.Is_Fee_Payer__c;
    link.portalAccess = rel.Portal_Access__c;
    link.isEmergencyContact = rel.Is_Emergency_Contact__c;
    return link;
  }
}
