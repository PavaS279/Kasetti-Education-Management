/**
 * Generates PDF documents (offer letter, invoice, receipt, report card) from Visualforce
 * templates and files them on the record as Salesforce Files.
 *
 * A document is generated once and then reused, so the version that was sent
 * is preserved. Rendering a page counts as a callout, which Salesforce does not
 * allow after uncommitted DML; automatic generation after an offer, an invoice
 * issue, or a payment confirmation therefore runs in DocumentService.Job.
 */
public with sharing class DocumentService {
  public static final String OFFER_LETTER = 'Offer Letter';
  public static final String INVOICE = 'Invoice';
  public static final String RECEIPT = 'Receipt';
  public static final String REPORT_CARD = 'Report Card';
  public static final String HALL_TICKET = 'Hall Ticket';
  /** College: provisional admission letter (fee and deadline), filed on the admission. */
  public static final String COLLEGE_ADMISSION_LETTER = 'College Admission Letter';
  /** College: admission confirmed with the roll number, filed on the admission. */
  public static final String COLLEGE_CONFIRMATION_LETTER = 'College Admission Confirmation';
  private static final String SUPERSEDED = ' (superseded)';
  private static final String MARKER = 'KEM ';

  @TestVisible
  private static Boolean suppressJobs = false;

  public class DocumentInfo {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String kind;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String createdBy;
  }

  /** Returns the document of this kind for the record, generating it the first time. */
  public static Id generate(Id recordId, String kind) {
    Id existing = existing(recordId, kind);
    if (existing != null) {
      return existing;
    }
    ContentVersion version = render(recordId, kind);
    new Writer().insertVersions(new List<ContentVersion>{ version });
    return [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :version.Id
      WITH SYSTEM_MODE
    ]
    .ContentDocumentId;
  }

  public static Id existing(Id recordId, String kind) {
    for (ContentDocumentLink link : links(recordId)) {
      if (
        link.ContentDocument.LatestPublishedVersion.Description == MARKER + kind
      ) {
        return link.ContentDocumentId;
      }
    }
    return null;
  }

  /** KEM-generated documents filed on a record, newest first. */
  public static List<DocumentInfo> documentsFor(Id recordId) {
    assertReadable(recordId);
    List<DocumentInfo> result = new List<DocumentInfo>();
    for (ContentDocumentLink link : links(recordId)) {
      String description = link.ContentDocument.LatestPublishedVersion.Description;
      if (description == null || !description.startsWith(MARKER)) {
        continue;
      }
      DocumentInfo info = new DocumentInfo();
      info.contentDocumentId = link.ContentDocumentId;
      info.title = link.ContentDocument.Title;
      info.kind = description.removeStart(MARKER);
      info.createdDate = link.ContentDocument.CreatedDate;
      info.createdBy = link.ContentDocument.CreatedBy.Name;
      result.add(info);
    }
    return result;
  }

  /** Queues generation (used right after the DML that made the document due). */
  public static void enqueue(Set<Id> recordIds, String kind) {
    recordIds.remove(null);
    if (
      recordIds.isEmpty() ||
      suppressJobs ||
      Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()
    ) {
      return;
    }
    System.enqueueJob(new Job(recordIds, kind));
  }

  public static String kindFor(Id recordId) {
    SObjectType type = recordId.getSObjectType();
    if (type == IndividualApplication.SObjectType) {
      String college = collegeLetterKind(recordId);
      return college == null ? OFFER_LETTER : college;
    }
    if (type == Student_Invoice__c.SObjectType) {
      return INVOICE;
    }
    if (type == Student_Payment__c.SObjectType) {
      return RECEIPT;
    }
    if (type == CourseOfferingParticipant.SObjectType) {
      return REPORT_CARD;
    }
    if (type == Exam_Candidate__c.SObjectType) {
      return HALL_TICKET;
    }
    throw new AppException('Documents are not available for this record.');
  }

  /**
   * Marks issued documents of this kind as superseded (they stay on the record
   * for history) so that the next generation issues a new version.
   */
  public static void supersede(Set<Id> recordIds, String kind, String reason) {
    recordIds.remove(null);
    if (recordIds.isEmpty()) {
      return;
    }
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT
        ContentDocumentId,
        ContentDocument.LatestPublishedVersion.Description
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :recordIds
      WITH SYSTEM_MODE
    ]) {
      if (
        link.ContentDocument.LatestPublishedVersion.Description == MARKER + kind
      ) {
        documentIds.add(link.ContentDocumentId);
      }
    }
    List<ContentVersion> versions = new List<ContentVersion>();
    for (ContentVersion version : [
      SELECT Id
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
      WITH SYSTEM_MODE
    ]) {
      version.Description = (MARKER +
        kind +
        SUPERSEDED +
        ': ' +
        reason)
        .left(1000);
      versions.add(version);
    }
    new Writer().updateVersions(versions);
  }

  // --------------------------------------------------------------- helpers

  /**
   * The letter a college admission currently has: confirmation once enrolled,
   * the provisional admission letter while the fee is pending; null for school
   * applications.
   */
  private static String collegeLetterKind(Id applicationId) {
    IndividualApplication application = [
      SELECT College_Mode__c
      FROM IndividualApplication
      WHERE Id = :applicationId
      WITH SYSTEM_MODE
    ];
    if (application.College_Mode__c != true) {
      return null;
    }
    Programme_Enrolment__c enrolment = collegeEnrolment(applicationId);
    return enrolment != null &&
      enrolment.Status__c == 'Enrolled'
      ? COLLEGE_CONFIRMATION_LETTER
      : COLLEGE_ADMISSION_LETTER;
  }

  public static Programme_Enrolment__c collegeEnrolment(Id applicationId) {
    List<Programme_Enrolment__c> enrolments = [
      SELECT Id, Status__c, Roll_Number__c
      FROM Programme_Enrolment__c
      WHERE Application__c = :applicationId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return enrolments.isEmpty() ? null : enrolments[0];
  }

  /**
   * College letters are generated automatically when the Dean admits and when
   * Finance confirms the fee. Finance does not share the private college
   * admissions, so the letter is allowed to anyone who can read the admission
   * or who manages billing (and already sees the same student and fee on the
   * invoice). Every other document still requires read access.
   */
  public static void assertCollegeLetterAccess(Id applicationId) {
    if (FeatureManagement.checkPermission(BillingService.MANAGE_PERMISSION)) {
      return;
    }
    assertReadable(applicationId);
  }

  private static ContentVersion render(Id recordId, String kind) {
    PageReference page = pageFor(kind);
    page.getParameters().put('id', recordId);
    page.getParameters().put('kind', kind);
    String title = titleFor(recordId, kind);
    Blob pdf = Test.isRunningTest()
      ? Blob.valueOf('PDF ' + title)
      : page.getContentAsPDF();
    return new ContentVersion(
      Title = title,
      PathOnClient = title.replaceAll('[^A-Za-z0-9 _-]', '') + '.pdf',
      VersionData = pdf,
      Description = MARKER + kind,
      FirstPublishLocationId = recordId
    );
  }

  private static PageReference pageFor(String kind) {
    if (kind == OFFER_LETTER) {
      return Page.KEM_Offer_Letter;
    }
    if (kind == INVOICE) {
      return Page.KEM_Invoice_Pdf;
    }
    if (kind == RECEIPT) {
      return Page.KEM_Receipt_Pdf;
    }
    if (kind == REPORT_CARD) {
      return Page.KEM_Report_Card;
    }
    if (kind == HALL_TICKET) {
      return Page.KEM_Hall_Ticket;
    }
    if (
      kind == COLLEGE_ADMISSION_LETTER ||
      kind == COLLEGE_CONFIRMATION_LETTER
    ) {
      return Page.KEM_College_Admission_Letter;
    }
    throw new AppException('Unknown document type: ' + kind);
  }

  /** Builds the file title and checks that the running user can read the record. */
  private static String titleFor(Id recordId, String kind) {
    if (
      kind == COLLEGE_ADMISSION_LETTER ||
      kind == COLLEGE_CONFIRMATION_LETTER
    ) {
      return collegeLetterTitle(recordId, kind);
    }
    assertReadable(recordId);
    if (kind == OFFER_LETTER) {
      IndividualApplication application = [
        SELECT Name, Offer_Status__c, Account.Name
        FROM IndividualApplication
        WHERE Id = :recordId
        WITH SYSTEM_MODE
      ];
      if (
        application.Offer_Status__c == null ||
        application.Offer_Status__c == 'Not Offered'
      ) {
        throw new AppException(
          'An offer letter is available once an offer is made.'
        );
      }
      return 'Offer Letter ' +
        application.Name +
        ' - ' +
        application.Account.Name;
    }
    if (kind == INVOICE) {
      Student_Invoice__c invoice = [
        SELECT Name, Status__c
        FROM Student_Invoice__c
        WHERE Id = :recordId
        WITH SYSTEM_MODE
      ];
      if (invoice.Status__c == 'Draft' || invoice.Status__c == 'Cancelled') {
        throw new AppException('Only issued invoices have a PDF.');
      }
      return 'Invoice ' + invoice.Name;
    }
    if (kind == REPORT_CARD) {
      CourseOfferingParticipant enrolment = [
        SELECT Grade_Status__c, ParticipantContact.Name, CourseOffering.Name
        FROM CourseOfferingParticipant
        WHERE Id = :recordId
        WITH SYSTEM_MODE
      ];
      if (enrolment.Grade_Status__c != 'Final') {
        throw new AppException(
          'A report card is issued once the class grades are final.'
        );
      }
      return 'Report Card ' +
        enrolment.ParticipantContact.Name +
        ' - ' +
        enrolment.CourseOffering.Name;
    }
    if (kind == HALL_TICKET) {
      Exam_Candidate__c candidate = [
        SELECT Name, Status__c, Learner_Account__r.Name, Exam__r.Name
        FROM Exam_Candidate__c
        WHERE Id = :recordId
        WITH SYSTEM_MODE
      ];
      if (candidate.Status__c != 'Ticket Issued') {
        throw new AppException('A hall ticket is available once it is issued.');
      }
      return 'Hall Ticket ' +
        candidate.Name +
        ' - ' +
        candidate.Learner_Account__r.Name;
    }
    Student_Payment__c payment = [
      SELECT Receipt_Number__c, Status__c
      FROM Student_Payment__c
      WHERE Id = :recordId
      WITH SYSTEM_MODE
    ];
    if (payment.Status__c != 'Confirmed') {
      throw new AppException(
        'A receipt is available once the payment is confirmed.'
      );
    }
    return 'Receipt ' + payment.Receipt_Number__c;
  }

  private static String collegeLetterTitle(Id applicationId, String kind) {
    assertCollegeLetterAccess(applicationId);
    IndividualApplication application = [
      SELECT Name, Account.Name
      FROM IndividualApplication
      WHERE Id = :applicationId AND College_Mode__c = TRUE
      WITH SYSTEM_MODE
    ];
    Programme_Enrolment__c enrolment = collegeEnrolment(applicationId);
    if (kind == COLLEGE_CONFIRMATION_LETTER) {
      if (enrolment == null || enrolment.Status__c != 'Enrolled') {
        throw new AppException(
          'The confirmation letter is issued once the fee is received.'
        );
      }
      return 'Admission Confirmation ' +
        enrolment.Roll_Number__c +
        ' - ' +
        application.Account.Name;
    }
    if (
      enrolment == null ||
      (enrolment.Status__c != 'Provisional' &&
      enrolment.Status__c != 'Enrolled')
    ) {
      throw new AppException(
        'The admission letter is issued once the Dean admits the student.'
      );
    }
    return 'Admission Letter ' +
      application.Name +
      ' - ' +
      application.Account.Name;
  }

  private static void assertReadable(Id recordId) {
    List<UserRecordAccess> access = [
      SELECT RecordId, HasReadAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId
    ];
    if (access.isEmpty() || !access[0].HasReadAccess) {
      throw new AppException('Record not found or not accessible.');
    }
  }

  private static List<ContentDocumentLink> links(Id recordId) {
    return [
      SELECT
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.CreatedDate,
        ContentDocument.CreatedBy.Name,
        ContentDocument.LatestPublishedVersion.Description
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :recordId
      WITH SYSTEM_MODE
      ORDER BY ContentDocument.CreatedDate DESC
    ];
  }

  /** Renders documents asynchronously, after the triggering transaction committed. */
  public with sharing class Job implements Queueable, Database.AllowsCallouts {
    private final Set<Id> recordIds;
    private final String kind;

    public Job(Set<Id> recordIds, String kind) {
      this.recordIds = recordIds;
      this.kind = kind;
    }

    public void execute(QueueableContext context) {
      List<ContentVersion> versions = new List<ContentVersion>();
      for (Id recordId : recordIds) {
        try {
          if (existing(recordId, kind) == null) {
            versions.add(render(recordId, kind));
          }
        } catch (Exception e) {
          Logger.error('DocumentService.Job', e, recordId);
        }
      }
      new Writer().insertVersions(versions);
    }
  }

  /** Files are written after the caller's read access to the record was checked. */
  private without sharing class Writer {
    void updateVersions(List<ContentVersion> versions) {
      if (!versions.isEmpty()) {
        Database.update(versions, AccessLevel.SYSTEM_MODE);
      }
    }

    void insertVersions(List<ContentVersion> versions) {
      if (!versions.isEmpty()) {
        Database.insert(versions, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
