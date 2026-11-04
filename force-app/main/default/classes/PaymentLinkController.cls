/** Lightning controller for online payment links on the invoice page (finance staff). */
public with sharing class PaymentLinkController {
  public class Panel {
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public Boolean webhookConfigured;
    @AuraEnabled
    public List<Payment_Link__c> links = new List<Payment_Link__c>();
  }

  @AuraEnabled
  public static Panel getPanel(Id invoiceId) {
    try {
      Panel panel = new Panel();
      panel.mode = PaymentLinkService.mode();
      panel.webhookConfigured = PaymentLinkService.webhookConfigured();
      panel.links = [
        SELECT
          Id,
          Name,
          Amount__c,
          Status__c,
          Expires_On__c,
          Created_Via__c,
          Gateway_Reference__c,
          CreatedDate
        FROM Payment_Link__c
        WHERE Invoice__c = :invoiceId
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT 20
      ];
      return panel;
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static PaymentLinkService.LinkView createLink(Id invoiceId) {
    try {
      return PaymentLinkService.createForStaff(invoiceId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void simulate(Id linkId) {
    try {
      PaymentLinkService.simulate(linkId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
