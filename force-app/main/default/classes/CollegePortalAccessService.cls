/**
 * Portal access for college students, run by the admission desk.
 *
 * At Admit, and when the counsellor clicks Give portal access, a Portal Access
 * Request event is published. Its trigger runs as an administrator (the
 * counsellor has no user-management rights) and creates the login when the
 * student has an email address and a portal licence is free; the welcome email
 * carries the link to set a password. Only admitted college students (fee
 * pending or enrolled) qualify.
 */
public with sharing class CollegePortalAccessService {
  private static final Set<String> ADMITTED = new Set<String>{
    'Fee Pending',
    'Enrolled'
  };
  /** Tests switch the automatic job on explicitly; elsewhere it always runs. */
  @TestVisible
  private static Boolean autoInTests = false;

  public class Status {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean canGive = false;
    @AuraEnabled
    public Boolean canResend = false;
  }

  /** Portal state of the admission's student, and what the desk may do now. */
  public static Status status(IndividualApplication a) {
    if (!ADMITTED.contains(a.College_Stage__c)) {
      return null; // shown from Admit onwards
    }
    Status s = new Status();
    Reader reader = new Reader();
    Account p = reader.student(a.AccountId);
    User login = p?.Users?.isEmpty() == false ? p.Users[0] : null;
    Boolean desk = FeatureManagement.checkPermission(
      CollegeDocumentService.VERIFY_PERMISSION
    );
    if (login != null) {
      s.label = login.IsActive ? 'Active' : 'Deactivated';
      s.canResend = desk && login.IsActive;
    } else if (p == null || String.isBlank(p.PersonEmail)) {
      s.label = 'Needs an email';
    } else if (PortalAccessService.freeLicences() < 1) {
      s.label = 'No free portal licence';
    } else {
      s.label = 'Not given';
      s.canGive = desk;
    }
    return s;
  }

  /** The counsellor's button: asks for the login to be created. */
  public static void request(Id applicationId) {
    publish(authorise(applicationId));
  }

  public static String sendPasswordLink(Id applicationId) {
    return PortalAccessService.sendPasswordLinkInternal(
      authorise(applicationId)
    );
  }

  /** Called at Admit: the event is delivered only if the admission commits. */
  public static void queueAutoAccess(Id studentId) {
    if (studentId == null || (Test.isRunningTest() && !autoInTests)) {
      return;
    }
    publish(studentId);
  }

  private static void publish(Id studentId) {
    EventBus.publish(
      new Portal_Access_Request__e(
        Account_Id__c = studentId,
        Requested_By__c = UserInfo.getUserId()
      )
    );
  }

  /**
   * Trigger handler (runs as the administrator). The owner fix and the login
   * cannot be saved together, so a changed owner republishes the request.
   */
  public static void handleRequests(List<Portal_Access_Request__e> requests) {
    for (Portal_Access_Request__e r : requests) {
      Id studentId = (Id) r.Account_Id__c;
      try {
        Reader reader = new Reader();
        Account p = reader.student(studentId);
        if (
          p == null ||
          String.isBlank(p.PersonEmail) ||
          !p.Users.isEmpty() ||
          PortalAccessService.freeLicences() < 1
        ) {
          continue; // the panel shows why; the desk can ask again later
        }
        if (PortalAccessService.prepareInternal(studentId)) {
          publish(studentId);
          continue;
        }
        PortalAccessService.giveInternal(studentId, true);
      } catch (Exception e) {
        Logger.error('CollegePortalAccessService', e, studentId);
      }
    }
  }

  /** The admission's student, after checking the desk may act on it. */
  private static Id authorise(Id applicationId) {
    RecordAccess.assertPermission(CollegeDocumentService.VERIFY_PERMISSION);
    IndividualApplication a = [
      SELECT AccountId, College_Mode__c, College_Stage__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (!a.College_Mode__c || !ADMITTED.contains(a.College_Stage__c)) {
      throw new AppException(
        'Portal access is given once the student is admitted.'
      );
    }
    return a.AccountId;
  }

  private without sharing class Reader {
    Account student(Id accountId) {
      List<Account> rows = [
        SELECT
          Id,
          PersonEmail,
          PersonContactId,
          (SELECT Id, IsActive FROM Users LIMIT 1)
        FROM Account
        WHERE Id = :accountId AND IsPersonAccount = TRUE
        WITH SYSTEM_MODE
      ];
      return rows.isEmpty() ? null : rows[0];
    }
  }
}
