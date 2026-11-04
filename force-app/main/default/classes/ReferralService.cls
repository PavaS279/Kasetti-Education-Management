/**
 * Alumni and referrals (F4.11).
 *
 * Families and alumni get a personal referral code. An enquiry that gives a
 * code (staff, website form or enquiry API) is linked to the referrer and a
 * Referral is recorded; when the referred learner enrols for the first time
 * the referral is marked Enrolled, and a reward credit can be granted to
 * the referrer (automatically when Referral_Reward_Mode is Auto, otherwise
 * by staff on the referrals desk). Learners who complete a class and have
 * no other active enrolment become alumni; alumni can be invited back.
 */
public with sharing class ReferralService {
  public static final String ENQUIRED = 'Enquired';
  public static final String ENROLLED = 'Enrolled';
  public static final String REWARDED = 'Rewarded';
  public static final String NOT_ELIGIBLE = 'Not Eligible';
  // No 0/O or 1/I/L: codes are read out and typed by families.
  private static final String ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  public class ReferralRow {
    @AuraEnabled
    public Id referralId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String referrer;
    @AuraEnabled
    public Id referrerId;
    @AuraEnabled
    public String referred;
    @AuraEnabled
    public Id enquiryId;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Date enrolledOn;
    @AuraEnabled
    public Decimal reward;
    @AuraEnabled
    public String creditNote;
    @AuraEnabled
    public Datetime createdDate;
  }

  public class ReferrerRow {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String code;
    @AuraEnabled
    public Integer referrals = 0;
    @AuraEnabled
    public Integer enrolled = 0;
  }

  public class AlumnusRow {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date since;
    @AuraEnabled
    public String branch;
    @AuraEnabled
    public Boolean contactOk;
    @AuraEnabled
    public String code;
  }

  public class Desk {
    @AuraEnabled
    public Map<String, Integer> counts = new Map<String, Integer>();
    @AuraEnabled
    public List<ReferralRow> referrals = new List<ReferralRow>();
    @AuraEnabled
    public List<ReferrerRow> topReferrers = new List<ReferrerRow>();
    @AuraEnabled
    public List<AlumnusRow> alumni = new List<AlumnusRow>();
    @AuraEnabled
    public Integer alumniTotal = 0;
    @AuraEnabled
    public Decimal rewardAmount;
    @AuraEnabled
    public String rewardMode;
    @AuraEnabled
    public Boolean canReward = false;
    @AuraEnabled
    public Decimal conversionRate;
  }

  // ---------------------------------------------------------------- settings

  public static Decimal rewardAmount() {
    return AppSettings.getDecimal('Referral_Reward_Amount', 500);
  }

  /** Off (no rewards), Manual (staff grant) or Auto (granted on enrolment). */
  public static String rewardMode() {
    return AppSettings.getString('Referral_Reward_Mode', 'Manual');
  }

  // ---------------------------------------------------------------- codes

  /** The account's referral code, created when it has none. */
  public static String codeFor(Id accountId) {
    // Staff must be able to see the account.
    Account a = [
      SELECT Id, LastName, Name, Referral_Code__c
      FROM Account
      WHERE Id = :accountId
      WITH USER_MODE
    ];
    return ensureCode(a);
  }

  /** For the portal, after it has identified the signed-in person. */
  public static String codeForViewer(Id accountId) {
    return ensureCode(
      [
        SELECT Id, LastName, Name, Referral_Code__c
        FROM Account
        WHERE Id = :accountId
        WITH SYSTEM_MODE
      ]
    );
  }

  private static String ensureCode(Account a) {
    if (String.isNotBlank(a.Referral_Code__c)) {
      return a.Referral_Code__c;
    }
    String base = (String.isBlank(a.LastName) ? a.Name : a.LastName)
      .toUpperCase()
      .replaceAll('[^A-Z]', '');
    base = (base + 'KEM').left(3);
    for (Integer attempt = 0; attempt < 5; attempt++) {
      String code = base + '-' + randomPart(4);
      if (
        [
          SELECT COUNT()
          FROM Account
          WHERE Referral_Code__c = :code
          WITH SYSTEM_MODE
        ] == 0
      ) {
        new Writer()
          .updateRecords(
            new List<SObject>{ new Account(Id = a.Id, Referral_Code__c = code) }
          );
        return code;
      }
    }
    throw new AppException(
      'Could not create a unique referral code. Please try again.'
    );
  }

  private static String randomPart(Integer length) {
    String result = '';
    for (Integer i = 0; i < length; i++) {
      Integer index = Math.mod(
        Math.abs(Crypto.getRandomInteger()),
        ALPHABET.length()
      );
      result += ALPHABET.substring(index, index + 1);
    }
    return result;
  }

  public static String normalise(String code) {
    return String.isBlank(code)
      ? null
      : code.trim().toUpperCase().replaceAll('\\s+', '');
  }

  // ---------------------------------------------------------------- enquiries

  /** Before insert of enquiries: links a valid code to its referrer. */
  public static void resolveCodes(List<Lead> leads) {
    Map<String, List<Lead>> byCode = new Map<String, List<Lead>>();
    for (Lead l : leads) {
      String code = normalise(l.Referral_Code__c);
      if (code == null) {
        continue;
      }
      l.Referral_Code__c = code;
      if (!byCode.containsKey(code)) {
        byCode.put(code, new List<Lead>());
      }
      byCode.get(code).add(l);
    }
    if (byCode.isEmpty()) {
      return;
    }
    // Codes are public by design; the referrer is read in system mode.
    for (Account a : [
      SELECT Id, Referral_Code__c
      FROM Account
      WHERE Referral_Code__c IN :byCode.keySet()
      WITH SYSTEM_MODE
    ]) {
      for (Lead l : byCode.get(a.Referral_Code__c)) {
        l.Referred_By__c = a.Id;
        l.Enquiry_Channel__c = 'Referral';
      }
    }
  }

  /** After insert of enquiries: records a referral for each referred enquiry. */
  public static void recordReferrals(List<Lead> leads) {
    List<Referral__c> inserts = new List<Referral__c>();
    for (Lead l : leads) {
      if (l.Referred_By__c == null) {
        continue;
      }
      inserts.add(
        new Referral__c(
          Referrer__c = l.Referred_By__c,
          Enquiry__c = l.Id,
          Branch__c = l.Branch__c,
          Code_Used__c = l.Referral_Code__c,
          Status__c = ENQUIRED
        )
      );
    }
    new Writer().insertRecords(inserts);
  }

  // ---------------------------------------------------------------- enrolments

  /**
   * After enrolments are created: a referred learner's first enrolment
   * completes the referral (and grants the reward in Auto mode).
   */
  public static void onEnrolments(List<CourseOfferingParticipant> enrolments) {
    Map<Id, CourseOfferingParticipant> byLearner = new Map<Id, CourseOfferingParticipant>();
    for (CourseOfferingParticipant e : enrolments) {
      if (
        e.ParticipantAccountId != null &&
        !byLearner.containsKey(e.ParticipantAccountId)
      ) {
        byLearner.put(e.ParticipantAccountId, e);
      }
    }
    if (byLearner.isEmpty()) {
      return;
    }
    List<Referral__c> open = [
      SELECT Id, Referrer__c, Enquiry__r.Converted_Learner__c, Branch__c
      FROM Referral__c
      WHERE
        Status__c = :ENQUIRED
        AND Enquiry__r.Converted_Learner__c IN :byLearner.keySet()
      WITH SYSTEM_MODE
    ];
    if (open.isEmpty()) {
      return;
    }
    List<SObject> updates = new List<SObject>();
    for (Referral__c r : open) {
      CourseOfferingParticipant e = byLearner.get(
        r.Enquiry__r.Converted_Learner__c
      );
      updates.add(
        new Referral__c(
          Id = r.Id,
          Status__c = ENROLLED,
          Enrolled_On__c = Date.today(),
          Enrolment__c = e.Id,
          Referred_Learner__c = e.ParticipantAccountId
        )
      );
    }
    new Writer().updateRecords(updates);
    if (rewardMode() == 'Auto') {
      for (Referral__c r : open) {
        try {
          reward(r.Id, true);
        } catch (Exception ex) {
          Logger.warn(
            'ReferralService',
            'Reward not granted: ' + ex.getMessage(),
            r.Id
          );
        }
      }
    }
  }

  /**
   * After enrolments change: learners who completed a class and have no
   * other active enrolment become alumni.
   */
  public static void markAlumni(
    List<CourseOfferingParticipant> changed,
    Map<Id, SObject> oldMap
  ) {
    Set<Id> learners = new Set<Id>();
    for (CourseOfferingParticipant e : changed) {
      CourseOfferingParticipant before = (CourseOfferingParticipant) oldMap.get(
        e.Id
      );
      if (
        e.ParticipationStatus == 'Completed' &&
        before.ParticipationStatus != 'Completed'
      ) {
        learners.add(e.ParticipantAccountId);
      }
    }
    learners.remove(null);
    if (learners.isEmpty()) {
      return;
    }
    for (CourseOfferingParticipant active : [
      SELECT ParticipantAccountId
      FROM CourseOfferingParticipant
      WHERE
        ParticipantAccountId IN :learners
        AND ParticipationStatus IN :RetentionService.ACTIVE
      WITH SYSTEM_MODE
    ]) {
      learners.remove(active.ParticipantAccountId);
    }
    List<SObject> updates = new List<SObject>();
    for (Account a : [
      SELECT Id
      FROM Account
      WHERE Id IN :learners AND Alumni__c = FALSE
      WITH SYSTEM_MODE
    ]) {
      updates.add(
        new Account(Id = a.Id, Alumni__c = true, Alumni_Since__c = Date.today())
      );
    }
    new Writer().updateRecords(updates);
  }

  // ---------------------------------------------------------------- rewards

  /** Grants the reward credit for an enrolled referral (once). */
  public static Id reward(Id referralId, Boolean automatic) {
    if (!automatic) {
      RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    }
    if (rewardMode() == 'Off') {
      throw new AppException(
        'Referral rewards are switched off (Referral_Reward_Mode).'
      );
    }
    Referral__c r = [
      SELECT
        Id,
        Status__c,
        Referrer__c,
        Referrer__r.Name,
        Referrer__r.PersonContactId,
        Branch__c,
        Referred_Learner__r.Name,
        Enquiry__r.Name
      FROM Referral__c
      WHERE Id = :referralId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (r.Status__c != ENROLLED) {
      throw new AppException(
        r.Status__c == REWARDED
          ? 'This referral has already been rewarded.'
          : 'Only referrals that led to an enrolment can be rewarded.'
      );
    }
    if (r.Referrer__r.PersonContactId == null) {
      throw new AppException(
        'The referrer is not a person, so no credit can be issued.'
      );
    }
    Decimal amount = rewardAmount();
    String referred = r.Referred_Learner__r?.Name != null
      ? r.Referred_Learner__r.Name
      : r.Enquiry__r?.Name;
    Id noteId = CreditService.issueReferralCredit(
      r.Referrer__r.PersonContactId,
      r.Branch__c,
      amount,
      'Referral reward for ' + referred
    );
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Referral__c(
            Id = r.Id,
            Status__c = REWARDED,
            Reward_Amount__c = amount,
            Credit_Note__c = noteId,
            Rewarded_On__c = Date.today()
          )
        }
      );
    MessageService.Notice n = new MessageService.Notice();
    n.recipientId = r.Referrer__r.PersonContactId;
    n.branchId = r.Branch__c;
    n.relatedId = r.Id;
    n.values.put('ReferredName', referred);
    n.values.put('Amount', MessageService.money(amount));
    MessageService.notify(
      'Referral_Reward',
      new List<MessageService.Notice>{ n }
    );
    return noteId;
  }

  public static void markNotEligible(Id referralId, String note) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    Referral__c r = [
      SELECT Id, Status__c, Notes__c
      FROM Referral__c
      WHERE Id = :referralId
      WITH USER_MODE
    ];
    if (r.Status__c == REWARDED) {
      throw new AppException(
        'A rewarded referral cannot be marked not eligible.'
      );
    }
    new Writer()
      .updateRecords(
        new List<SObject>{
          new Referral__c(
            Id = r.Id,
            Status__c = NOT_ELIGIBLE,
            Notes__c = String.isBlank(note) ? r.Notes__c : note.left(255)
          )
        }
      );
  }

  // ---------------------------------------------------------------- desk

  public static Desk desk(Id branchId) {
    Desk d = new Desk();
    d.rewardAmount = rewardAmount();
    d.rewardMode = rewardMode();
    d.canReward =
      FeatureManagement.checkPermission(BillingService.MANAGE_PERMISSION) &&
      d.rewardMode != 'Off';
    for (
      String s : new List<String>{ ENQUIRED, ENROLLED, REWARDED, NOT_ELIGIBLE }
    ) {
      d.counts.put(s, 0);
    }
    Map<String, Object> binds = new Map<String, Object>{
      'branchId' => branchId
    };
    String branch = branchId == null ? '' : ' WHERE Branch__c = :branchId';
    for (
      AggregateResult row : (List<AggregateResult>) Database.queryWithBinds(
        'SELECT Status__c status, COUNT(Id) total FROM Referral__c' +
          branch +
          ' GROUP BY Status__c',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      d.counts.put((String) row.get('status'), (Integer) row.get('total'));
    }
    Integer all = 0;
    for (Integer n : d.counts.values()) {
      all += n;
    }
    Integer converted = d.counts.get(ENROLLED) + d.counts.get(REWARDED);
    d.conversionRate = all == 0
      ? null
      : (Decimal.valueOf(converted) / all * 100).setScale(1);
    Map<Id, ReferrerRow> referrers = new Map<Id, ReferrerRow>();
    for (
      Referral__c r : (List<Referral__c>) Database.queryWithBinds(
        'SELECT Id, Name, Referrer__c, Referrer__r.Name, Referrer__r.Referral_Code__c, Enquiry__c, Enquiry__r.Name, ' +
          'Referred_Learner__r.Name, Branch__r.Name, Status__c, Enrolled_On__c, Reward_Amount__c, Credit_Note__r.Name, CreatedDate ' +
          'FROM Referral__c' +
          branch +
          ' ORDER BY CreatedDate DESC LIMIT 200',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      if (d.referrals.size() < 50) {
        ReferralRow row = new ReferralRow();
        row.referralId = r.Id;
        row.name = r.Name;
        row.referrer = r.Referrer__r?.Name;
        row.referrerId = r.Referrer__c;
        row.referred = r.Referred_Learner__r?.Name != null
          ? r.Referred_Learner__r.Name
          : r.Enquiry__r?.Name;
        row.enquiryId = r.Enquiry__c;
        row.branch = r.Branch__r?.Name;
        row.status = r.Status__c;
        row.enrolledOn = r.Enrolled_On__c;
        row.reward = r.Reward_Amount__c;
        row.creditNote = r.Credit_Note__r?.Name;
        row.createdDate = r.CreatedDate;
        d.referrals.add(row);
      }
      if (r.Referrer__c != null) {
        if (!referrers.containsKey(r.Referrer__c)) {
          ReferrerRow ref = new ReferrerRow();
          ref.accountId = r.Referrer__c;
          ref.name = r.Referrer__r?.Name;
          ref.code = r.Referrer__r?.Referral_Code__c;
          referrers.put(r.Referrer__c, ref);
        }
        ReferrerRow ref = referrers.get(r.Referrer__c);
        ref.referrals++;
        if (r.Status__c == ENROLLED || r.Status__c == REWARDED) {
          ref.enrolled++;
        }
      }
    }
    List<ReferrerRow> ranked = referrers.values();
    // Most enrolments first, then most referrals.
    for (Integer i = 0; i < ranked.size(); i++) {
      for (Integer j = i + 1; j < ranked.size(); j++) {
        ReferrerRow a = ranked[i];
        ReferrerRow b = ranked[j];
        if (
          b.enrolled > a.enrolled ||
          (b.enrolled == a.enrolled &&
          b.referrals > a.referrals)
        ) {
          ranked[i] = b;
          ranked[j] = a;
        }
      }
    }
    for (Integer i = 0; i < Math.min(5, ranked.size()); i++) {
      d.topReferrers.add(ranked[i]);
    }
    String alumniFilter =
      'Alumni__c = TRUE' +
      (branchId == null ? '' : ' AND Branch__c = :branchId');
    d.alumniTotal = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Account WHERE ' + alumniFilter,
      binds,
      AccessLevel.USER_MODE
    );
    for (
      Account a : (List<Account>) Database.queryWithBinds(
        'SELECT Id, Name, Alumni_Since__c, Branch__r.Name, Alumni_Contact_Ok__c, Referral_Code__c FROM Account WHERE ' +
          alumniFilter +
          ' ORDER BY Alumni_Since__c DESC NULLS LAST LIMIT 50',
        binds,
        AccessLevel.USER_MODE
      )
    ) {
      AlumnusRow row = new AlumnusRow();
      row.accountId = a.Id;
      row.name = a.Name;
      row.since = a.Alumni_Since__c;
      row.branch = a.Branch__r?.Name;
      row.contactOk = a.Alumni_Contact_Ok__c;
      row.code = a.Referral_Code__c;
      d.alumni.add(row);
    }
    return d;
  }

  /** Invites alumni back (those who allow contact), with their referral code. */
  public static Integer inviteAlumni(List<Id> accountIds, String message) {
    if (!Schema.SObjectType.Referral__c.isCreateable()) {
      throw new AppException('You do not have permission to contact alumni.');
    }
    if (accountIds == null || accountIds.isEmpty()) {
      throw new AppException('Choose the alumni to invite.');
    }
    List<Account> alumni = [
      SELECT Id, Name, PersonContactId, Branch__c
      FROM Account
      WHERE
        Id IN :accountIds
        AND Alumni__c = TRUE
        AND Alumni_Contact_Ok__c = TRUE
      WITH USER_MODE
    ];
    Set<Id> contacts = new Set<Id>();
    for (Account a : alumni) {
      contacts.add(a.PersonContactId);
    }
    Map<Id, Id> payers = MessageService.feePayersOf(contacts);
    List<MessageService.Notice> notices = new List<MessageService.Notice>();
    String stamp = String.valueOf(System.now().getTime());
    for (Account a : alumni) {
      MessageService.Notice n = new MessageService.Notice();
      Id payer = payers.get(a.PersonContactId);
      n.recipientId = payer == null ? a.PersonContactId : payer;
      n.learnerContactId = a.PersonContactId;
      n.learnerAccountId = a.Id;
      n.branchId = a.Branch__c;
      n.relatedId = a.Id;
      n.dedupSuffix = stamp;
      n.values.put('LearnerName', a.Name);
      n.values.put(
        'Message',
        String.isBlank(message) ? '' : message.trim().left(1000)
      );
      n.values.put('ReferralCode', codeFor(a.Id));
      notices.add(n);
    }
    return notices.isEmpty()
      ? 0
      : MessageService.notify('Alumni_Invite', notices);
  }

  /** System-mode writes of system-managed fields, after the checks above. */
  private without sharing class Writer {
    void insertRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
      }
    }
    void updateRecords(List<SObject> records) {
      if (!records.isEmpty()) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
