/** Lightning controller for generated documents (offer letters, invoices, receipts). */
public with sharing class DocumentController {
  @AuraEnabled
  public static List<DocumentService.DocumentInfo> getDocuments(Id recordId) {
    try {
      return DocumentService.documentsFor(recordId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  /** Returns the record's document, generating it the first time. */
  @AuraEnabled
  public static Id generateDocument(Id recordId) {
    try {
      return DocumentService.generate(
        recordId,
        DocumentService.kindFor(recordId)
      );
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
