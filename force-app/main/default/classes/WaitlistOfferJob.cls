/**
 * Hourly job: expires unanswered waitlist offers and offers their seats to the
 * next learners. Failures surface on the scheduled job (AsyncApexJob).
 * Schedule: KemJobs ('KEM Waitlist Offers', minute 5 of every hour).
 */
public with sharing class WaitlistOfferJob implements Schedulable {
  public void execute(SchedulableContext context) {
    Integer expired = WaitlistService.expireOffers();
    if (expired > 0) {
      Logger.info('WaitlistOfferJob', expired + ' waitlist offer(s) expired.');
      Logger.flush();
    }
  }
}
