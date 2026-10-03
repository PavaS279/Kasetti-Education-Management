/**
 * Admissions application lifecycle: checklist, eligibility, review, decision,
 * offer, and acceptance. Status, decision, and offer fields are system-managed:
 * the service checks the user's edit access to the application, then writes
 * them in system mode. Allowed transitions are enforced by the trigger.
 */
public with sharing class ApplicationService {
  public static final String DECISION_ADMIT = 'Admit';
  public static final String DECISION_WAITLIST = 'Waitlist';
  public static final String DECISION_REJECT = 'Reject';
  public static final String OVERRIDE_PERMISSION = 'KEM_Override_Eligibility';
  private static final Set<String> CLOSED_ITEM_STATUSES = new Set<String>{
    'Accepted',
    'Waived'
  };

  // ------------------------------------------------------------- checklist

  /** Creates checklist items from Application_Checklist_Item__mdt for new applications. */
  public static void createChecklists(Set<Id> applicationIds) {
    List<Application_Checklist_Item__mdt> template = new List<Application_Checklist_Item__mdt>();
    for (
      Application_Checklist_Item__mdt item : Application_Checklist_Item__mdt.getAll()
        .values()
    ) {
      if (item.Active__c) {
        template.add(item);
      }
    }
    if (template.isEmpty() || applicationIds.isEmpty()) {
      return;
    }
    List<DocumentChecklistItem> items = new List<DocumentChecklistItem>();
    for (Id applicationId : applicationIds) {
      for (Application_Checklist_Item__mdt item : template) {
        items.add(
          new DocumentChecklistItem(
            Name = item.MasterLabel,
            ParentRecordId = applicationId,
            IsRequired = item.Required__c,
            Instruction = item.Instruction__c,
            Status = 'New'
          )
        );
      }
    }
    // Derived records of the application: created in system mode for whoever creates it.
    // Checklist_Complete__c is already set in before insert, so the checklist
    // trigger is bypassed: updating the application from inside its own
    // after-insert trigger causes an internal error on IndividualApplication.
    TriggerHandler.bypass('DocumentChecklistItemTriggerHandler');
    try {
      Logger.errors(
        'ApplicationService.createChecklists',
        Database.insert(items, false, AccessLevel.SYSTEM_MODE)
      );
    } finally {
      TriggerHandler.clearBypass('DocumentChecklistItemTriggerHandler');
    }
  }

  /** True when the checklist template has no active required items. */
  public static Boolean templateHasNoRequiredItems() {
    for (
      Application_Checklist_Item__mdt item : Application_Checklist_Item__mdt.getAll()
        .values()
    ) {
      if (item.Active__c && item.Required__c) {
        return false;
      }
    }
    return true;
  }

  /** Sets Checklist_Complete__c when every required item is accepted or waived. */
  public static void refreshChecklistStatus(Set<Id> applicationIds) {
    if (applicationIds.isEmpty()) {
      return;
    }
    Map<Id, Boolean> complete = new Map<Id, Boolean>();
    for (Id applicationId : applicationIds) {
      complete.put(applicationId, true);
    }
    for (DocumentChecklistItem item : [
      SELECT ParentRecordId, Status, IsRequired
      FROM DocumentChecklistItem
      WHERE ParentRecordId IN :applicationIds AND IsRequired = TRUE
      WITH SYSTEM_MODE
    ]) {
      if (!CLOSED_ITEM_STATUSES.contains(item.Status)) {
        complete.put(item.ParentRecordId, false);
      }
    }
    List<IndividualApplication> updates = new List<IndividualApplication>();
    for (IndividualApplication application : [
      SELECT Id, Checklist_Complete__c
      FROM IndividualApplication
      WHERE Id IN :applicationIds
      WITH SYSTEM_MODE
    ]) {
      if (application.Checklist_Complete__c != complete.get(application.Id)) {
        updates.add(
          new IndividualApplication(
            Id = application.Id,
            Checklist_Complete__c = complete.get(application.Id)
          )
        );
      }
    }
    if (!updates.isEmpty()) {
      Database.update(updates, AccessLevel.SYSTEM_MODE);
    }
  }

  public static void updateChecklistItem(
    Id itemId,
    String status,
    String rejectReason
  ) {
    if (status == 'Rejected' && String.isBlank(rejectReason)) {
      throw new AppException('Enter a reason when rejecting a checklist item.');
    }
    ChecklistItemGateway.updateStatus(
      new DocumentChecklistItem(
        Id = itemId,
        Status = status,
        RejectReason = status == 'Rejected' ? rejectReason.left(255) : null
      )
    );
  }

  public static Id addChecklistItem(
    Id applicationId,
    String name,
    Boolean required,
    String instruction
  ) {
    if (String.isBlank(name)) {
      throw new AppException('Enter a name for the checklist item.');
    }
    DocumentChecklistItem item = new DocumentChecklistItem(
      Name = name.left(255),
      ParentRecordId = applicationId,
      IsRequired = required == true,
      Instruction = instruction,
      Status = 'New'
    );
    Database.insert(item, AccessLevel.USER_MODE);
    return item.Id;
  }

  // ----------------------------------------------------------- eligibility

  /** Evaluates age-based eligibility against the course limits (before-trigger safe: no DML). */
  public static void evaluateEligibility(
    List<IndividualApplication> applications
  ) {
    Set<Id> courseIds = new Set<Id>();
    Set<Id> accountIds = new Set<Id>();
    for (IndividualApplication application : applications) {
      if (application.Learning_Course__c != null) {
        courseIds.add(application.Learning_Course__c);
      }
      if (application.AccountId != null) {
        accountIds.add(application.AccountId);
      }
    }
    if (courseIds.isEmpty()) {
      return;
    }
    Map<Id, LearningCourse> courses = new Map<Id, LearningCourse>(
      [
        SELECT Id, Name, Minimum_Age__c, Maximum_Age__c
        FROM LearningCourse
        WHERE Id IN :courseIds
        WITH SYSTEM_MODE
      ]
    );
    Map<Id, Account> learners = new Map<Id, Account>(
      [
        SELECT Id, PersonBirthdate
        FROM Account
        WHERE Id IN :accountIds
        WITH SYSTEM_MODE
      ]
    );
    for (IndividualApplication application : applications) {
      LearningCourse course = courses.get(application.Learning_Course__c);
      if (course == null) {
        continue;
      }
      Account learner = learners.get(application.AccountId);
      EligibilityResult result = checkAge(
        course,
        learner == null ? null : learner.PersonBirthdate,
        Date.today()
      );
      application.Eligibility_Status__c = result.status;
      application.Eligibility_Notes__c = result.notes;
    }
  }

  public class EligibilityResult {
    public String status;
    public String notes;
  }

  @TestVisible
  private static EligibilityResult checkAge(
    LearningCourse course,
    Date birthdate,
    Date onDate
  ) {
    EligibilityResult result = new EligibilityResult();
    if (course.Minimum_Age__c == null && course.Maximum_Age__c == null) {
      result.status = 'Eligible';
      result.notes = 'No age requirement for ' + course.Name + '.';
      return result;
    }
    if (birthdate == null) {
      result.status = 'Not Checked';
      result.notes = 'Learner date of birth is missing; age limits cannot be checked.';
      return result;
    }
    Integer age = ageOn(birthdate, onDate);
    Boolean tooYoung =
      course.Minimum_Age__c != null &&
      age < course.Minimum_Age__c;
    Boolean tooOld =
      course.Maximum_Age__c != null &&
      age > course.Maximum_Age__c;
    result.status = tooYoung || tooOld ? 'Not Eligible' : 'Eligible';
    result.notes =
      'Age ' +
      age +
      '; course range ' +
      (course.Minimum_Age__c == null
        ? 'any'
        : String.valueOf(course.Minimum_Age__c.intValue())) +
      '–' +
      (course.Maximum_Age__c == null
        ? 'any'
        : String.valueOf(course.Maximum_Age__c.intValue())) +
      '.';
    return result;
  }

  @TestVisible
  private static Integer ageOn(Date birthdate, Date onDate) {
    Integer age = onDate.year() - birthdate.year();
    if (
      onDate.month() < birthdate.month() ||
      (onDate.month() == birthdate.month() &&
      onDate.day() < birthdate.day())
    ) {
      age--;
    }
    return age;
  }

  public static void overrideEligibility(Id applicationId, String notes) {
    RecordAccess.assertPermission(OVERRIDE_PERMISSION);
    RecordAccess.assertEditable(applicationId);
    if (String.isBlank(notes)) {
      throw new AppException(
        'Explain why the eligibility check is overridden.'
      );
    }
    write(
      new IndividualApplication(
        Id = applicationId,
        Eligibility_Status__c = 'Overridden',
        Eligibility_Notes__c = ('Overridden by ' +
          UserInfo.getName() +
          ': ' +
          notes)
          .left(255)
      )
    );
  }

  // ------------------------------------------------------- review/decision

  public static void submitForReview(Id applicationId) {
    IndividualApplication application = load(applicationId);
    assertStatus(application, 'Processing');
    write(
      new IndividualApplication(
        Id = applicationId,
        Status = 'In Review',
        Reviewer__c = application.Reviewer__c == null
          ? UserInfo.getUserId()
          : application.Reviewer__c
      )
    );
  }

  public static void returnToApplicant(Id applicationId) {
    IndividualApplication application = load(applicationId);
    assertStatus(application, 'In Review');
    write(
      new IndividualApplication(
        Id = applicationId,
        Status = 'Processing',
        WasReturned = true
      )
    );
  }

  public static void markReadyForDecision(Id applicationId) {
    IndividualApplication application = load(applicationId);
    assertStatus(application, 'In Review');
    if (!application.Checklist_Complete__c) {
      throw new AppException(
        'All required checklist items must be accepted or waived first.'
      );
    }
    if (application.Eligibility_Status__c == 'Not Eligible') {
      throw new AppException(
        'The applicant is not eligible. Override eligibility with a reason to continue.'
      );
    }
    write(
      new IndividualApplication(
        Id = applicationId,
        Status = 'Ready For Decision',
        RequirementsCompleteDate = System.now()
      )
    );
  }

  public static void decide(
    Id applicationId,
    String decision,
    String reason,
    Integer offerValidDays
  ) {
    IndividualApplication application = load(applicationId);
    assertStatus(application, 'Ready For Decision');
    if (
      !new Set<String>{ DECISION_ADMIT, DECISION_WAITLIST, DECISION_REJECT }
        .contains(decision)
    ) {
      throw new AppException('Choose Admit, Waitlist, or Reject.');
    }
    if (decision != DECISION_ADMIT && String.isBlank(reason)) {
      throw new AppException(
        'Enter a reason for a ' + decision.toLowerCase() + ' decision.'
      );
    }
    IndividualApplication changes = new IndividualApplication(
      Id = applicationId,
      Status = 'Application Decision',
      Decision__c = decision,
      Decision_Reason__c = reason == null ? null : reason.left(255),
      Decision_Date__c = System.now(),
      Decided_By__c = UserInfo.getUserId()
    );
    if (decision == DECISION_ADMIT) {
      Integer days = offerValidDays != null &&
        offerValidDays > 0
        ? offerValidDays
        : AppSettings.getInteger('Offer_Validity_Days', 14);
      changes.Offer_Status__c = 'Offered';
      changes.Offer_Expiry_Date__c = Date.today().addDays(days);
      changes.ApprovedDate = System.now();
    }
    write(changes);
    if (decision == DECISION_ADMIT) {
      DocumentService.enqueue(
        new Set<Id>{ applicationId },
        DocumentService.OFFER_LETTER
      );
    }
  }

  public static void respondToOffer(Id applicationId, Boolean accept) {
    IndividualApplication application = load(applicationId);
    if (application.Offer_Status__c != 'Offered') {
      throw new AppException('There is no open offer on this application.');
    }
    if (
      application.Offer_Expiry_Date__c != null &&
      application.Offer_Expiry_Date__c < Date.today()
    ) {
      throw new AppException(
        'The offer expired on ' +
          application.Offer_Expiry_Date__c.format() +
          '.'
      );
    }
    write(
      new IndividualApplication(
        Id = applicationId,
        Offer_Status__c = accept ? 'Accepted' : 'Declined',
        Offer_Responded_Date__c = System.now()
      )
    );
  }

  public static void withdraw(Id applicationId, String reason) {
    IndividualApplication application = load(applicationId);
    if (
      new Set<String>{ 'Withdrawn', 'Canceled', 'Cancelled', 'Enrolled' }
        .contains(application.Status)
    ) {
      throw new AppException('This application is already closed.');
    }
    if (String.isBlank(reason)) {
      throw new AppException('Enter a reason for withdrawing the application.');
    }
    write(
      new IndividualApplication(
        Id = applicationId,
        Status = 'Withdrawn',
        Decision_Reason__c = reason.left(255)
      )
    );
  }

  /** Marks an accepted application as enrolled (called by EnrolmentService). */
  public static void markEnrolled(Id applicationId) {
    IndividualApplication application = load(applicationId);
    if (application.Status == 'Enrolled') {
      return;
    }
    write(new IndividualApplication(Id = applicationId, Status = 'Enrolled'));
  }

  /** Expires open offers whose expiry date has passed. Used by OfferExpiryJob. */
  public static Integer expireOffers(List<IndividualApplication> applications) {
    List<IndividualApplication> updates = new List<IndividualApplication>();
    for (IndividualApplication application : applications) {
      if (
        application.Offer_Status__c == 'Offered' &&
        application.Offer_Expiry_Date__c < Date.today()
      ) {
        updates.add(
          new IndividualApplication(
            Id = application.Id,
            Offer_Status__c = 'Expired'
          )
        );
      }
    }
    Logger.errors(
      'ApplicationService.expireOffers',
      Database.update(updates, false, AccessLevel.SYSTEM_MODE)
    );
    return updates.size();
  }

  // --------------------------------------------------------------- helpers

  public static IndividualApplication load(Id applicationId) {
    List<IndividualApplication> applications = [
      SELECT
        Id,
        Name,
        Status,
        Reviewer__c,
        Checklist_Complete__c,
        Eligibility_Status__c,
        Eligibility_Notes__c,
        Offer_Status__c,
        Offer_Expiry_Date__c,
        Decision__c,
        AccountId,
        ContactId,
        Branch__c,
        Learning_Course__c,
        Requested_Offering__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH USER_MODE
    ];
    if (applications.isEmpty()) {
      throw new AppException('Application not found or not accessible.');
    }
    return applications[0];
  }

  private static void assertStatus(
    IndividualApplication application,
    String expected
  ) {
    if (application.Status != expected) {
      throw new AppException(
        'This action requires the application to be in ' +
          expected +
          ' (it is ' +
          application.Status +
          ').'
      );
    }
  }

  /** Writes system-managed fields after confirming the user may edit the record. */
  private static void write(IndividualApplication changes) {
    RecordAccess.assertEditable(changes.Id);
    Database.SaveResult result = Database.update(
      changes,
      false,
      AccessLevel.SYSTEM_MODE
    );
    if (!result.isSuccess()) {
      throw new AppException(result.getErrors()[0].getMessage());
    }
  }
}
