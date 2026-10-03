/**
 * Payment gateway / bank notification endpoint (runs as the integration user,
 * who needs the KEM Finance persona).
 *
 * POST /services/apexrest/kem/v1/payments
 * {
 *   "transactionId": "pay_Nx81...",   // gateway transaction ID (required, idempotency key)
 *   "invoiceNumber": "BLR-000042",    // required
 *   "amount": 12500.00,               // required
 *   "status": "success" | "pending" | "failed",
 *   "method": "Online Gateway",       // optional, default Online Gateway
 *   "paidOn": "2026-10-03"            // optional
 * }
 * A repeated transactionId returns the original payment (HTTP 200, duplicate=true);
 * a later "success" for a pending transaction confirms it.
 */
@RestResource(urlMapping='/kem/v1/payments')
global with sharing class PaymentApi {
  global class PaymentNotification {
    public String transactionId;
    public String invoiceNumber;
    public Decimal amount;
    public String status;
    public String method;
    public Date paidOn;
  }

  global class PaymentResponse {
    public Id paymentId;
    public String status;
    public String reconciliationStatus;
    public String receiptNumber;
    public Boolean duplicate;
    public String error;
  }

  @HttpPost
  global static void notifyPayment() {
    RestResponse response = RestContext.response;
    response.addHeader('Content-Type', 'application/json');
    PaymentResponse body = new PaymentResponse();
    try {
      PaymentNotification note = (PaymentNotification) JSON.deserialize(
        RestContext.request.requestBody.toString(),
        PaymentNotification.class
      );
      BillingService.PaymentResult outcome = process(note);
      body.paymentId = outcome.paymentId;
      body.status = outcome.status;
      body.reconciliationStatus = outcome.reconciliationStatus;
      body.receiptNumber = outcome.receiptNumber;
      body.duplicate = outcome.duplicate;
      response.statusCode = outcome.duplicate ? 200 : 201;
    } catch (AppException e) {
      body.error = e.getMessage();
      response.statusCode = 400;
    } catch (JSONException e) {
      body.error = 'Malformed JSON: ' + e.getMessage();
      response.statusCode = 400;
    } catch (Exception e) {
      Logger.error('PaymentApi.notifyPayment', e, null);
      body.error =
        'The payment could not be recorded. Reference: ' +
        Request.getCurrent().getRequestId();
      response.statusCode = 500;
    }
    response.responseBody = Blob.valueOf(JSON.serialize(body, true));
  }

  @TestVisible
  private static BillingService.PaymentResult process(
    PaymentNotification note
  ) {
    if (note == null || String.isBlank(note.transactionId)) {
      throw new AppException('transactionId is required.');
    }
    if (String.isBlank(note.invoiceNumber)) {
      throw new AppException('invoiceNumber is required.');
    }
    String status = String.isBlank(note.status)
      ? 'success'
      : note.status.toLowerCase();
    if (!new Set<String>{ 'success', 'pending', 'failed' }.contains(status)) {
      throw new AppException('status must be success, pending, or failed.');
    }
    List<Student_Invoice__c> invoices = [
      SELECT Id
      FROM Student_Invoice__c
      WHERE Name = :note.invoiceNumber
      WITH USER_MODE
      LIMIT 1
    ];
    if (invoices.isEmpty()) {
      throw new AppException('Unknown invoiceNumber: ' + note.invoiceNumber);
    }
    BillingService.PaymentRequest request = new BillingService.PaymentRequest();
    request.invoiceId = invoices[0].Id;
    request.amount = note.amount;
    request.method = String.isBlank(note.method)
      ? 'Online Gateway'
      : note.method;
    request.gatewayTransactionId = note.transactionId;
    request.paymentDate = note.paidOn;
    request.confirmed = status == 'success';
    BillingService.PaymentResult outcome = BillingService.recordPayment(
      request
    );
    // A later notification moves a pending transaction on.
    if (outcome.duplicate && outcome.status == 'Pending') {
      if (status == 'success') {
        outcome = BillingService.confirmPayment(outcome.paymentId);
        outcome.duplicate = false;
      } else if (status == 'failed') {
        BillingService.failPayment(
          outcome.paymentId,
          'Gateway reported the transaction as failed.'
        );
        outcome.status = 'Failed';
        outcome.duplicate = false;
      }
    } else if (!outcome.duplicate && status == 'failed') {
      BillingService.failPayment(
        outcome.paymentId,
        'Gateway reported the transaction as failed.'
      );
      outcome.status = 'Failed';
    }
    return outcome;
  }
}
