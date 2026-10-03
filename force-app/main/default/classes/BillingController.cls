/** Lightning controller for invoices, payments, and the Finance Desk. */
public with sharing class BillingController {
  @AuraEnabled
  public static Id createInvoice(Id enrolmentId, Boolean issueNow) {
    try {
      return BillingService.createInvoice(enrolmentId, issueNow);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void issueInvoice(Id invoiceId) {
    try {
      BillingService.issue(invoiceId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void cancelInvoice(Id invoiceId, String reason) {
    try {
      BillingService.cancel(invoiceId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BillingService.PaymentResult recordPayment(
    BillingService.PaymentRequest request
  ) {
    try {
      return BillingService.recordPayment(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BillingService.PaymentResult confirmPayment(Id paymentId) {
    try {
      return BillingService.confirmPayment(paymentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void failPayment(Id paymentId, String reason) {
    try {
      BillingService.failPayment(paymentId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BillingService.PaymentResult resolveException(
    Id paymentId,
    String note
  ) {
    try {
      return BillingService.resolveException(paymentId, note);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BillingService.InvoiceView getInvoice(Id invoiceId) {
    try {
      return BillingService.getInvoice(invoiceId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Student_Invoice__c> getLearnerInvoices(
    Id learnerAccountId
  ) {
    try {
      return BillingService.learnerInvoices(learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static BillingService.FinanceDesk getFinanceDesk() {
    try {
      return BillingService.financeDesk();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
