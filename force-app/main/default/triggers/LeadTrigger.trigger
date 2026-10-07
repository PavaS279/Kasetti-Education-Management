trigger LeadTrigger on Lead(
  before insert,
  before update,
  after insert,
  after update
) {
  new LeadTriggerHandler().run();
}
