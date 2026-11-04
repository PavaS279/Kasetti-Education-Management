/** Lightning controller for credit notes and refunds. */
public with sharing class CreditController {
  @AuraEnabled
  public static Id issueCreditNote(CreditService.CreditRequest request) {
    try {
      return CreditService.issueForInvoice(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id holdOverpayment(Id paymentId) {
    try {
      return CreditService.holdOverpayment(paymentId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void voidCreditNote(Id creditNoteId, String reason) {
    try {
      CreditService.voidNote(creditNoteId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Decimal applyCredit(
    Id creditNoteId,
    Id invoiceId,
    Decimal amount
  ) {
    try {
      return CreditService.apply(creditNoteId, invoiceId, amount);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static Id requestRefund(CreditService.RefundRequest request) {
    try {
      return CreditService.requestRefund(request);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void approveRefund(Id refundId) {
    try {
      CreditService.approveRefund(refundId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void rejectRefund(Id refundId, String reason) {
    try {
      CreditService.rejectRefund(refundId, reason);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static void markRefundPaid(
    Id refundId,
    String reference,
    Date paidOn
  ) {
    try {
      CreditService.markRefundPaid(refundId, reference, paidOn);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CreditService.CreditView getCreditNote(Id creditNoteId) {
    try {
      return CreditService.getCreditNote(creditNoteId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled
  public static CreditService.RefundQueue getRefundQueue() {
    try {
      return CreditService.refundQueue();
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Credit_Note__c> getLearnerCredits(Id learnerAccountId) {
    try {
      return CreditService.learnerCredits(learnerAccountId);
    } catch (Exception e) {
      throw AppException.toAura(e);
    }
  }
}
