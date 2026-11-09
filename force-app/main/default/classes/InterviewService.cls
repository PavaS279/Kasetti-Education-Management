/**
 * College admission decisions.
 *
 * An eligible applicant is admitted by the admission counsellor once the
 * documents are verified; the Dean is not involved. Only an applicant who does
 * not meet the criteria goes to the Dean: the counsellor requests an exception
 * with a reason, and the Dean approves or declines it, with an optional
 * interview first. Admissions already in the old interview flow (Interview
 * Scheduled / Ready For Decision) finish the old way.
 */
public with sharing class InterviewService {
  public static final String PERMISSION = 'KEM_Conduct_Interview';
  public static final String AWAITING_DEAN = 'Awaiting Dean Approval';
  private static final Set<String> MEETS_CRITERIA = new Set<String>{
    'Eligible',
    'Overridden'
  };

  /** True when the counsellor may admit: documents verified and eligible, or Dean-approved. */
  public static Boolean admissible(IndividualApplication a) {
    if (a.College_Stage__c == 'Ready For Decision') {
      return a.Interview_Outcome__c == 'Pass';
    }
    return a.College_Stage__c == 'Documents Verified' &&
      (MEETS_CRITERIA.contains(a.Eligibility_Status__c) ||
      a.Exception_Status__c == 'Approved');
  }

  /** True when the applicant does not meet the criteria and has no exception yet. */
  public static Boolean needsException(IndividualApplication a) {
    return a.College_Stage__c == 'Documents Verified' &&
      !MEETS_CRITERIA.contains(a.Eligibility_Status__c) &&
      a.Exception_Status__c == null;
  }

  /** Counsellor asks the Dean to admit an applicant who does not meet the criteria. */
  public static void requestException(Id applicationId, String reason) {
    RecordAccess.assertPermission(CollegeDocumentService.VERIFY_PERMISSION);
    RecordAccess.assertEditable(applicationId);
    IndividualApplication application = admission(applicationId);
    // The reason typed when the admission was created is used when none is given now.
    if (String.isBlank(reason)) {
      reason = application.Exception_Reason__c;
    }
    if (String.isBlank(reason)) {
      throw new AppException('Enter why the Dean should admit this applicant.');
    }
    if (
      needsException(application) &&
      application.Campus_Branch__r?.Dean_Exceptions_Allowed__c == false
    ) {
      throw new AppException(
        'Dean exceptions are switched off for this branch in the college admission setup.'
      );
    }
    if (!needsException(application)) {
      throw new AppException(
        MEETS_CRITERIA.contains(application.Eligibility_Status__c)
          ? 'This applicant meets the criteria; admit them without the Dean.'
          : 'Verify the documents before asking the Dean for an exception.'
      );
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = AWAITING_DEAN,
        Exception_Status__c = 'Requested',
        Exception_Reason__c = reason.trim().left(2000),
        Exception_Requested_By__c = UserInfo.getUserId()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  /** Dean approves the exception: the counsellor can now admit. */
  public static void approveException(Id applicationId, String remarks) {
    authorise(applicationId);
    IndividualApplication application = admission(applicationId);
    assertAwaitingDean(application);
    decideException(applicationId, 'Approved', remarks, 'Documents Verified');
  }

  /** Dean declines the exception: the admission closes as rejected. */
  public static void declineException(Id applicationId, String reason) {
    authorise(applicationId);
    if (String.isBlank(reason)) {
      throw new AppException('Enter the reason for declining the exception.');
    }
    IndividualApplication application = admission(applicationId);
    assertAwaitingDean(application);
    decideException(applicationId, 'Declined', reason, 'Application Decision');
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        Decision__c = 'Reject',
        Decision_Reason__c = 'Dean declined the exception: ' + reason.trim(),
        Decided_By__c = UserInfo.getUserId(),
        Decision_Date__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void assertAwaitingDean(IndividualApplication application) {
    if (
      application.Exception_Status__c != 'Requested' ||
      (application.College_Stage__c != AWAITING_DEAN &&
      application.College_Stage__c != 'Interview Scheduled')
    ) {
      throw new AppException('There is no exception request to decide.');
    }
  }

  private static void decideException(
    Id applicationId,
    String decision,
    String remarks,
    String nextStage
  ) {
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = nextStage,
        Exception_Status__c = decision,
        Exception_Remarks__c = String.isBlank(remarks)
          ? null
          : remarks.trim().left(2000),
        Exception_Decided_By__c = UserInfo.getUserId(),
        Exception_Decided_On__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static void schedule(
    Id applicationId,
    Datetime interviewAt,
    Id interviewerId
  ) {
    authorise(applicationId);
    if (interviewAt == null || interviewerId == null) {
      throw new AppException('Choose the interview date and interviewer.');
    }
    IndividualApplication application = admission(applicationId);
    if (
      application.College_Stage__c != AWAITING_DEAN &&
      application.College_Stage__c != 'Documents Verified'
    ) {
      throw new AppException(
        'Verify the required documents before scheduling the interview.'
      );
    }
    List<User> interviewers = [
      SELECT Id
      FROM User
      WHERE Id = :interviewerId AND IsActive = TRUE
    ];
    if (interviewers.isEmpty()) {
      throw new AppException('Choose an active interviewer.');
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = 'Interview Scheduled',
        Interview_Date__c = interviewAt,
        Interviewer__c = interviewerId,
        Interview_Outcome__c = null,
        Interview_Remarks__c = null
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static void recordOutcome(
    Id applicationId,
    String outcome,
    String remarks
  ) {
    authorise(applicationId);
    IndividualApplication application = admission(applicationId);
    if (application.College_Stage__c != 'Interview Scheduled') {
      throw new AppException(
        'Schedule the interview before recording its outcome.'
      );
    }
    if (outcome != 'Pass' && outcome != 'Reject') {
      throw new AppException('Choose Pass or Reject as the interview outcome.');
    }
    if (
      application.Interview_Date__c == null ||
      application.Interviewer__c == null ||
      application.Interview_Date__c > System.now()
    ) {
      throw new AppException(
        'An outcome can be recorded only after the scheduled interview.'
      );
    }
    if (application.Exception_Status__c == 'Requested') {
      // An exception interview: the outcome is the Dean's decision.
      Database.update(
        new IndividualApplication(
          Id = applicationId,
          Interview_Outcome__c = outcome,
          Interview_Remarks__c = String.isBlank(remarks) ? null : remarks.trim()
        ),
        AccessLevel.SYSTEM_MODE
      );
      if (outcome == 'Pass') {
        decideException(
          applicationId,
          'Approved',
          remarks,
          'Documents Verified'
        );
      } else {
        String why = String.isBlank(remarks)
          ? 'Interview not passed.'
          : remarks;
        declineException(applicationId, why);
      }
      return;
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = 'Ready For Decision',
        Interview_Outcome__c = outcome,
        Interview_Remarks__c = String.isBlank(remarks) ? null : remarks.trim()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  public static Id admit(Id applicationId) {
    return ProgrammeEnrolmentService.admit(applicationId);
  }

  /** The counsellor (document desk) or the Dean may admit and reject. */
  public static void assertCanDecide(Id applicationId) {
    if (
      !FeatureManagement.checkPermission(PERMISSION) &&
      !FeatureManagement.checkPermission(
        CollegeDocumentService.VERIFY_PERMISSION
      )
    ) {
      RecordAccess.assertPermission(CollegeDocumentService.VERIFY_PERMISSION);
    }
    RecordAccess.assertEditable(applicationId);
  }

  /** Dean rejects an undecided college admission with a reason (not eligible or interview failed). */
  public static void reject(Id applicationId, String reason) {
    assertCanDecide(applicationId);
    if (String.isBlank(reason)) {
      throw new AppException('Enter the reason for rejecting the admission.');
    }
    IndividualApplication application = admission(applicationId);
    if (
      !new Set<String>{
          'Processing',
          'In Review',
          'Documents Verified',
          'Interview Scheduled',
          'Ready For Decision',
          AWAITING_DEAN
        }
        .contains(application.College_Stage__c)
    ) {
      throw new AppException('This admission has already been decided.');
    }
    Database.update(
      new IndividualApplication(
        Id = applicationId,
        College_Stage__c = 'Application Decision',
        Decision__c = 'Reject',
        Decision_Reason__c = reason.trim(),
        Decided_By__c = UserInfo.getUserId(),
        Decision_Date__c = System.now()
      ),
      AccessLevel.SYSTEM_MODE
    );
  }

  private static void authorise(Id applicationId) {
    RecordAccess.assertPermission(PERMISSION);
    RecordAccess.assertEditable(applicationId);
  }

  private static IndividualApplication admission(Id applicationId) {
    IndividualApplication result = [
      SELECT
        Id,
        College_Mode__c,
        College_Stage__c,
        Interview_Date__c,
        Interviewer__c,
        Interview_Outcome__c,
        Eligibility_Status__c,
        Exception_Status__c,
        Exception_Reason__c,
        Campus_Branch__r.Dean_Exceptions_Allowed__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (!result.College_Mode__c) {
      throw new AppException('Interviews apply only to college admissions.');
    }
    return result;
  }
}
