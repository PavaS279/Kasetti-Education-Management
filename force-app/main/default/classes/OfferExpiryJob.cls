/**
 * Nightly job that expires admission offers past their expiry date.
 * Schedule: System.schedule('KEM Offer Expiry', '0 30 1 * * ?', new OfferExpiryJob());
 */
public with sharing class OfferExpiryJob implements Database.Batchable<SObject>, Schedulable {
  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Offer_Status__c, Offer_Expiry_Date__c
        FROM IndividualApplication
        WHERE Offer_Status__c = 'Offered' AND Offer_Expiry_Date__c < TODAY
      ]
    );
  }

  public void execute(
    Database.BatchableContext context,
    List<IndividualApplication> scope
  ) {
    ApplicationService.expireOffers(scope);
  }

  public void finish(Database.BatchableContext context) {
    Logger.info(
      'OfferExpiryJob',
      'Offer expiry run completed: ' + context.getJobId()
    );
    Logger.flush();
  }

  public void execute(SchedulableContext context) {
    Database.executeBatch(new OfferExpiryJob(), 200);
  }
}
