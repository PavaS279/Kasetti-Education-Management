/**
 * Staff-side half of a family's admission document upload. Runs from the
 * Admission_Document__e trigger as the Automated Process user, because portal
 * licences cannot change Education Cloud checklist items: links the uploaded
 * file to the checklist item and marks the item Pending (awaiting staff
 * review). Never accepts, rejects or waives: those stay with staff.
 */
public without sharing class AdmissionDocumentService {
  private static final Set<String> DECIDED = new Set<String>{
    'Accepted',
    'Waived'
  };

  public static void attach(List<Admission_Document__e> events) {
    Map<Id, Id> documentByItem = new Map<Id, Id>();
    for (Admission_Document__e e : events) {
      if (
        String.isNotBlank(e.Item_Id__c) && String.isNotBlank(e.Document_Id__c)
      ) {
        documentByItem.put((Id) e.Item_Id__c, (Id) e.Document_Id__c);
      }
    }
    if (documentByItem.isEmpty()) {
      return;
    }
    Set<String> linked = new Set<String>();
    for (ContentDocumentLink link : [
      SELECT LinkedEntityId, ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :documentByItem.keySet()
      WITH SYSTEM_MODE
    ]) {
      linked.add(link.LinkedEntityId + ':' + link.ContentDocumentId);
    }
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    List<DocumentChecklistItem> pending = new List<DocumentChecklistItem>();
    for (DocumentChecklistItem item : [
      SELECT Id, Status
      FROM DocumentChecklistItem
      WHERE Id IN :documentByItem.keySet()
      WITH SYSTEM_MODE
    ]) {
      if (DECIDED.contains(item.Status)) {
        continue; // decided by staff after the upload was checked
      }
      Id documentId = documentByItem.get(item.Id);
      if (!linked.contains(item.Id + ':' + documentId)) {
        links.add(
          new ContentDocumentLink(
            ContentDocumentId = documentId,
            LinkedEntityId = item.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
          )
        );
      }
      if (item.Status != 'Pending') {
        pending.add(
          new DocumentChecklistItem(
            Id = item.Id,
            Status = 'Pending',
            RejectReason = null
          )
        );
      }
    }
    Database.insert(links, AccessLevel.SYSTEM_MODE);
    ChecklistItemGateway.updateStatusAsSystem(pending);
  }
}
