/**
 * Walk-in families and new applications (Phase 5 stage 4).
 *
 * A family is one or two guardians and one or more learners (person
 * accounts), every guardian linked to every learner. Before saving, the
 * screen checks for people who already exist (same email, or same last name
 * and phone) so staff can reuse them instead of creating duplicates. Each
 * learner can be enrolled in a class straight away or given an application
 * for a course. Everything is saved together or not at all.
 */
public with sharing class FamilySetupService {
  public class PersonInput {
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
    // Guardians
    @AuraEnabled
    public String relationship { get; set; }
    @AuraEnabled
    public Boolean isFeePayer { get; set; }
    @AuraEnabled
    public String preferredLanguage { get; set; }
    @AuraEnabled
    public String preferredChannel { get; set; }
    // Learners
    @AuraEnabled
    public Date birthdate { get; set; }
    @AuraEnabled
    public String school { get; set; }
    /** "none", "enrol" (offeringId) or "apply" (courseId, optional offeringId). */
    @AuraEnabled
    public String nextStep { get; set; }
    @AuraEnabled
    public Id offeringId { get; set; }
    @AuraEnabled
    public Id courseId { get; set; }
  }

  public class FamilyRequest {
    @AuraEnabled
    public Id branchId { get; set; }
    @AuraEnabled
    public String street { get; set; }
    @AuraEnabled
    public String city { get; set; }
    @AuraEnabled
    public String postalCode { get; set; }
    @AuraEnabled
    public List<PersonInput> guardians { get; set; }
    @AuraEnabled
    public List<PersonInput> learners { get; set; }
  }

  public class Match {
    @AuraEnabled
    public String kind; // guardian | learner
    @AuraEnabled
    public Integer index;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String detail;
  }

  public class FamilyResult {
    @AuraEnabled
    public List<Id> guardianIds = new List<Id>();
    @AuraEnabled
    public List<Id> learnerIds = new List<Id>();
    @AuraEnabled
    public List<Id> enrolmentIds = new List<Id>();
    @AuraEnabled
    public List<Id> applicationIds = new List<Id>();
    @AuraEnabled
    public Integer created = 0;
    @AuraEnabled
    public Integer reused = 0;
  }

  /** People who add families: they can create people and also applications or enrolments (not teachers). */
  private static void requireAccess() {
    if (
      !Schema.SObjectType.Account.isCreateable() ||
      !(Schema.SObjectType.IndividualApplication.isCreateable() ||
      Schema.SObjectType.CourseOfferingParticipant.isCreateable())
    ) {
      throw new AppException('You do not have access to add families.');
    }
  }

  /** People who already exist for the entered guardians and learners. */
  public static List<Match> findMatches(FamilyRequest r) {
    requireAccess();
    List<Match> matches = new List<Match>();
    if (r == null) {
      return matches;
    }
    addMatches(matches, 'guardian', r.guardians);
    addMatches(matches, 'learner', r.learners);
    return matches;
  }

  private static void addMatches(
    List<Match> matches,
    String kind,
    List<PersonInput> people
  ) {
    if (people == null) {
      return;
    }
    for (Integer i = 0; i < people.size(); i++) {
      PersonInput p = people[i];
      if (p.existingAccountId != null || String.isBlank(p.lastName)) {
        continue;
      }
      Account found = PersonAccountService.findPerson(
        blankToNull(p.email),
        blankToNull(p.phone),
        p.lastName.trim()
      );
      // Learners without contact details: same name and date of birth.
      if (found == null && kind == 'learner' && p.birthdate != null) {
        String first = p.firstName == null ? '' : p.firstName.trim();
        String last = p.lastName.trim();
        Date born = p.birthdate;
        for (Account a : [
          SELECT Id, Name, PersonEmail, PersonMobilePhone, PersonBirthdate
          FROM Account
          WHERE
            IsPersonAccount = TRUE
            AND FirstName = :first
            AND LastName = :last
            AND PersonBirthdate = :born
          WITH USER_MODE
          LIMIT 1
        ]) {
          found = a;
        }
      }
      if (found != null) {
        Account a = [
          SELECT
            Id,
            Name,
            PersonEmail,
            PersonMobilePhone,
            KEM_Role__c,
            Branch__r.Name
          FROM Account
          WHERE Id = :found.Id
          WITH USER_MODE
        ];
        Match m = new Match();
        m.kind = kind;
        m.index = i;
        m.accountId = a.Id;
        m.name = a.Name;
        List<String> bits = new List<String>();
        for (
          String s : new List<String>{
            a.KEM_Role__c,
            a.PersonEmail,
            a.PersonMobilePhone,
            a.Branch__r?.Name
          }
        ) {
          if (String.isNotBlank(s)) {
            bits.add(s);
          }
        }
        m.detail = String.join(bits, ' · ');
        matches.add(m);
      }
    }
  }

  /** Creates (or reuses) the people, links them and does each learner's next step. */
  public static FamilyResult createFamily(FamilyRequest r) {
    requireAccess();
    if (r == null || r.branchId == null) {
      throw new AppException('Choose the branch.');
    }
    List<PersonInput> guardians = named(r.guardians);
    List<PersonInput> learners = named(r.learners);
    if (learners.isEmpty()) {
      throw new AppException('Add at least one learner.');
    }
    for (PersonInput g : guardians) {
      if (
        g.existingAccountId == null &&
        String.isBlank(g.email) &&
        String.isBlank(g.phone)
      ) {
        throw new AppException(
          'Enter an email or mobile number for ' + nameOf(g) + '.'
        );
      }
    }
    for (PersonInput l : learners) {
      if (l.existingAccountId == null && l.birthdate == null) {
        throw new AppException(
          'Enter the date of birth of ' +
            nameOf(l) +
            ' (it decides which courses they can join).'
        );
      }
      if (l.birthdate != null && l.birthdate > Date.today()) {
        throw new AppException(
          'The date of birth of ' + nameOf(l) + ' is in the future.'
        );
      }
      if (l.nextStep == 'enrol' && l.offeringId == null) {
        throw new AppException('Choose the class for ' + nameOf(l) + '.');
      }
      if (l.nextStep == 'apply' && l.courseId == null) {
        throw new AppException(
          'Choose the course ' + nameOf(l) + ' applies for.'
        );
      }
    }

    FamilyResult result = new FamilyResult();
    Savepoint sp = Database.setSavepoint();
    try {
      List<Account> guardianAccounts = resolve(
        guardians,
        r,
        'Guardian',
        result
      );
      List<Account> learnerAccounts = resolve(learners, r, 'Learner', result);
      Map<Id, Account> people = PersonAccountService.reload(
        new Map<Id, Account>(concat(guardianAccounts, learnerAccounts)).keySet()
      );
      List<GuardianRelationshipService.GuardianLink> links = new List<GuardianRelationshipService.GuardianLink>();
      Boolean payerChosen = false;
      for (PersonInput g : guardians) {
        payerChosen = payerChosen || g.isFeePayer == true;
      }
      for (Integer gi = 0; gi < guardianAccounts.size(); gi++) {
        PersonInput g = guardians[gi];
        for (Account learner : learnerAccounts) {
          GuardianRelationshipService.GuardianLink link = new GuardianRelationshipService.GuardianLink();
          link.guardianContactId = people.get(guardianAccounts[gi].Id)
            .PersonContactId;
          link.learnerContactId = people.get(learner.Id).PersonContactId;
          link.relationship = String.isBlank(g.relationship)
            ? 'Guardian'
            : g.relationship;
          // The first guardian pays unless someone else was chosen.
          link.isFeePayer = payerChosen ? g.isFeePayer == true : gi == 0;
          links.add(link);
        }
      }
      if (!links.isEmpty()) {
        GuardianRelationshipService.link(links);
      }
      for (Account g : guardianAccounts) {
        result.guardianIds.add(g.Id);
      }
      for (Integer li = 0; li < learnerAccounts.size(); li++) {
        Id learnerId = learnerAccounts[li].Id;
        result.learnerIds.add(learnerId);
        PersonInput l = learners[li];
        if (l.nextStep == 'apply') {
          result.applicationIds.add(
            newApplication(learnerId, r.branchId, l.courseId, l.offeringId)
          );
        } else if (l.nextStep == 'enrol') {
          EnrolmentService.EnrolmentRequest e = new EnrolmentService.EnrolmentRequest();
          e.learnerAccountId = learnerId;
          e.offeringId = l.offeringId;
          result.enrolmentIds.add(EnrolmentService.enrol(e).enrolmentId);
        }
      }
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      throw e;
    }
  }

  private static List<Account> resolve(
    List<PersonInput> inputs,
    FamilyRequest r,
    String role,
    FamilyResult result
  ) {
    List<Account> accounts = new List<Account>();
    List<Account> toInsert = new List<Account>();
    List<Account> toUpdate = new List<Account>();
    Map<Id, Account> existing = new Map<Id, Account>();
    Set<Id> ids = new Set<Id>();
    for (PersonInput p : inputs) {
      if (p.existingAccountId != null) {
        ids.add(p.existingAccountId);
      }
    }
    if (!ids.isEmpty()) {
      existing = new Map<Id, Account>(
        [
          SELECT Id, KEM_Role__c, IsPersonAccount
          FROM Account
          WHERE Id IN :ids
          WITH USER_MODE
        ]
      );
    }
    for (PersonInput p : inputs) {
      Account a;
      if (p.existingAccountId != null) {
        a = existing.get(p.existingAccountId);
        if (a == null || !a.IsPersonAccount) {
          throw new AppException('The chosen existing person was not found.');
        }
        String merged = PersonAccountService.mergeRole(a.KEM_Role__c, role);
        if (merged != a.KEM_Role__c) {
          toUpdate.add(new Account(Id = a.Id, KEM_Role__c = merged));
        }
        result.reused++;
      } else {
        a = PersonAccountService.buildPerson(
          blankToNull(p.firstName),
          p.lastName.trim(),
          blankToNull(p.email),
          blankToNull(p.phone),
          r.branchId,
          role
        );
        a.PersonMailingStreet = blankToNull(r.street);
        a.PersonMailingCity = blankToNull(r.city);
        a.PersonMailingPostalCode = blankToNull(r.postalCode);
        a.PersonMailingCountry = 'India';
        if (role == 'Learner') {
          a.PersonBirthdate = p.birthdate;
          a.Description = String.isBlank(p.school)
            ? null
            : 'School: ' + p.school.trim();
        } else {
          a.Preferred_Language__pc = blankToNull(p.preferredLanguage);
          a.Preferred_Channel__pc = blankToNull(p.preferredChannel);
        }
        Id owner = PortalAccessService.portalOwnerId();
        if (owner != null) {
          // Portal logins need the account owner to have a role.
          a.OwnerId = owner;
        }
        toInsert.add(a);
        result.created++;
      }
      accounts.add(a);
    }
    Database.insert(toInsert, AccessLevel.USER_MODE);
    Database.update(toUpdate, AccessLevel.USER_MODE);
    return accounts;
  }

  // ------------------------------------------------------------ application

  /** An admissions application for a learner (as enquiry conversion makes them). */
  public static Id newApplication(
    Id learnerId,
    Id branchId,
    Id courseId,
    Id offeringId
  ) {
    if (!Schema.SObjectType.IndividualApplication.isCreateable()) {
      throw new AppException('You do not have access to create applications.');
    }
    if (learnerId == null || courseId == null) {
      throw new AppException('Choose the learner and the course.');
    }
    Account learner = [
      SELECT Id, PersonContactId, KEM_Role__c, Branch__c, Name
      FROM Account
      WHERE Id = :learnerId
      WITH USER_MODE
    ];
    if (!LearnerService.isLearner(learner.KEM_Role__c)) {
      throw new AppException(learner.Name + ' is not a learner.');
    }
    if (
      [
        SELECT COUNT()
        FROM IndividualApplication
        WHERE
          AccountId = :learnerId
          AND Learning_Course__c = :courseId
          AND Status IN ('Processing', 'In Review', 'Ready For Decision')
        WITH SYSTEM_MODE
      ] > 0
    ) {
      throw new AppException(
        learner.Name + ' already has an open application for this course.'
      );
    }
    Schema.RecordTypeInfo admissions = Schema.SObjectType.IndividualApplication.getRecordTypeInfosByDeveloperName()
      .get('Admissions');
    IndividualApplication app = new IndividualApplication(
      Category = 'Education',
      AccountId = learner.Id,
      ContactId = learner.PersonContactId,
      Status = 'Processing',
      AppliedDate = System.now(),
      Branch__c = branchId == null ? learner.Branch__c : branchId,
      Learning_Course__c = courseId,
      Requested_Offering__c = offeringId
    );
    if (admissions != null) {
      app.RecordTypeId = admissions.getRecordTypeId();
    }
    Database.insert(app, AccessLevel.USER_MODE);
    return app.Id;
  }

  // ---------------------------------------------------------------- choices

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

  public class Choices {
    @AuraEnabled
    public List<Option> branches = new List<Option>();
    @AuraEnabled
    public List<Option> courses = new List<Option>();
    @AuraEnabled
    public List<Option> classes = new List<Option>();
    @AuraEnabled
    public Id defaultBranchId;
    @AuraEnabled
    public Boolean canEnrol;
    @AuraEnabled
    public Boolean canApply;
  }

  /** Branches, active courses and (for a branch) classes open for enrolment with seats. */
  public static Choices choices(Id branchId) {
    Choices c = new Choices();
    for (Branch__c b : [
      SELECT Id, Name
      FROM Branch__c
      WHERE Active__c = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 200
    ]) {
      c.branches.add(new Option(b.Name, b.Id, null));
    }
    for (Branch_Staff__c s : [
      SELECT Branch__c
      FROM Branch_Staff__c
      WHERE User__c = :UserInfo.getUserId() AND Active__c = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ]) {
      c.defaultBranchId = s.Branch__c;
    }
    for (LearningCourse course : [
      SELECT Id, Name, Minimum_Age__c, Maximum_Age__c
      FROM LearningCourse
      WHERE IsActive = TRUE
      WITH USER_MODE
      ORDER BY Name
      LIMIT 500
    ]) {
      String ages = course.Minimum_Age__c == null &&
        course.Maximum_Age__c == null
        ? null
        : 'Ages ' +
          (course.Minimum_Age__c == null
            ? '–'
            : String.valueOf(course.Minimum_Age__c.intValue())) +
          '–' +
          (course.Maximum_Age__c == null
            ? ''
            : String.valueOf(course.Maximum_Age__c.intValue()));
      c.courses.add(new Option(course.Name, course.Id, ages));
    }
    Id branch = branchId == null ? c.defaultBranchId : branchId;
    if (branch != null) {
      for (CourseOffering o : [
        SELECT Id, Name, Seats_Available__c, LearningCourseId
        FROM CourseOffering
        WHERE Branch__c = :branch AND Class_Status__c IN ('Open', 'In Progress')
        WITH USER_MODE
        ORDER BY Name
        LIMIT 200
      ]) {
        Integer seats = o.Seats_Available__c == null
          ? null
          : o.Seats_Available__c.intValue();
        c.classes.add(
          new Option(
            o.Name +
            (seats == null
              ? ''
              : (seats <= 0 ? ' (full)' : ' (' + seats + ' seats free)')),
            o.Id,
            o.LearningCourseId
          )
        );
      }
    }
    c.canEnrol = Schema.SObjectType.CourseOfferingParticipant.isCreateable();
    c.canApply = Schema.SObjectType.IndividualApplication.isCreateable();
    return c;
  }

  // ---------------------------------------------------------------- helpers

  private static List<PersonInput> named(List<PersonInput> people) {
    List<PersonInput> out = new List<PersonInput>();
    for (PersonInput p : people == null ? new List<PersonInput>() : people) {
      if (p.existingAccountId != null || String.isNotBlank(p.lastName)) {
        out.add(p);
      }
    }
    return out;
  }

  private static List<Account> concat(List<Account> a, List<Account> b) {
    List<Account> all = new List<Account>(a);
    all.addAll(b);
    return all;
  }

  private static String nameOf(PersonInput p) {
    return ((p.firstName == null ? '' : p.firstName.trim() + ' ') +
      (p.lastName == null ? '' : p.lastName.trim()))
      .trim();
  }

  private static String blankToNull(String value) {
    return String.isBlank(value) ? null : value.trim();
  }
}
