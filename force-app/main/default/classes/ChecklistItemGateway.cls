/**
 * Single point for changing DocumentChecklistItem status.
 *
 * Updating DocumentChecklistItem.Status inside an Apex test raises an
 * uncatchable "Internal Salesforce Error" in this org (updates of other fields,
 * inserts, and deletes work, and the same update works outside tests). Unit
 * tests therefore enable simulateStatusUpdates, which replaces the item with an
 * equivalent one in the new status so the checklist triggers and completion
 * logic are still exercised. The real update path is verified end to end in
 * the org. See docs/adr/ADR-004-checklist-status-test-seam.md.
 */
public inherited sharing class ChecklistItemGateway {
  @TestVisible
  private static Boolean simulateStatusUpdates = false;

  public static void updateStatus(DocumentChecklistItem change) {
    if (simulateStatusUpdates && Test.isRunningTest()) {
      simulate(change);
      return;
    }
    Database.update(change, AccessLevel.USER_MODE);
  }

  private static void simulate(DocumentChecklistItem change) {
    DocumentChecklistItem existing = [
      SELECT Id, Name, ParentRecordId, IsRequired, Instruction
      FROM DocumentChecklistItem
      WHERE Id = :change.Id
      WITH USER_MODE
    ];
    Database.delete(existing, AccessLevel.USER_MODE);
    Database.insert(
      new DocumentChecklistItem(
        Name = existing.Name,
        ParentRecordId = existing.ParentRecordId,
        IsRequired = existing.IsRequired,
        Instruction = existing.Instruction,
        Status = change.Status,
        RejectReason = change.RejectReason
      ),
      AccessLevel.USER_MODE
    );
  }
}
