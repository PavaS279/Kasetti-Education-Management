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
      return OFFER_LETTER;
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

  private static ContentVersion render(Id recordId, String kind) {
    PageReference page = pageFor(kind);
    page.getParameters().put('id', recordId);
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
    throw new AppException('Unknown document type: ' + kind);
  }

  /** Builds the file title and checks that the running user can read the record. */
  private static String titleFor(Id recordId, String kind) {
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
