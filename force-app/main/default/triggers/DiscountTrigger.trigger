trigger DiscountTrigger on Discount__c(before insert, before update) {
  new DiscountTriggerHandler().run();
}
