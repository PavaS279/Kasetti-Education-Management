trigger DocumentChecklistItemTrigger on DocumentChecklistItem(
  after insert,
  after update,
  after delete,
  after undelete
) {
  new DocumentChecklistItemTriggerHandler().run();
}
