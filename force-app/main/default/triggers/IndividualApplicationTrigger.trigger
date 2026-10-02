trigger IndividualApplicationTrigger on IndividualApplication(
  before insert,
  before update,
  after insert
) {
  new IndividualApplicationTriggerHandler().run();
}
