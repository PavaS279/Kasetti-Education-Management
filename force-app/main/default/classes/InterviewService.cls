/** Dean-governed scheduling and outcome capture for college admissions. */
public with sharing class InterviewService {
  public static final String PERMISSION = 'KEM_Conduct_Interview';

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
    if (application.College_Stage__c != 'Documents Verified') {
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
    authorise(applicationId);
    return ProgrammeEnrolmentService.admit(applicationId);
  }

  /** Dean rejects an undecided college admission with a reason (not eligible or interview failed). */
  public static void reject(Id applicationId, String reason) {
    authorise(applicationId);
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
          'Ready For Decision'
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
        Interviewer__c
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
