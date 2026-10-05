/** Lightning controller for the learner message timeline, staff messages and email consent. */
public with sharing class MessageController {
  @AuraEnabled
  public static MessageService.Timeline getTimeline(Id learnerAccountId) {
    try {
      return MessageService.timeline(learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static List<Id> sendMessage(MessageService.StaffMessage request) {
    try {
      return MessageService.sendStaffMessage(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void setEmailOptOut(
    Id learnerAccountId,
    Id contactId,
    Boolean optedOut
  ) {
    try {
      MessageService.setEmailOptOut(learnerAccountId, contactId, optedOut);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
