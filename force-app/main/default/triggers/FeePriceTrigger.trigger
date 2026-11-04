trigger FeePriceTrigger on Fee_Price__c(before insert, before update) {
  new FeePriceTriggerHandler().run();
}
