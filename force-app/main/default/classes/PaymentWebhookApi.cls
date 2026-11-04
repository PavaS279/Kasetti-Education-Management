/**
 * Payment gateway webhook for portal payment links (integration user with
 * the KEM Integration persona; typically called by gateway middleware).
 *
 * POST /services/apexrest/kem/v1/payments/webhook
 * Header  X-KEM-Signature: hex HMAC-SHA256 of the raw body with the shared
 *         secret (Setup → Custom Settings → KEM Gateway → Webhook Secret)
 * Body    { "token": "...", "transactionId": "pay_123", "amount": 1180.00, "status": "success" | "failed" }
 *
 * 200 recorded (duplicate=true when the transaction was already recorded),
 * 400 invalid request, 401 bad signature, 503 webhook not configured.
 */
@RestResource(urlMapping='/kem/v1/payments/webhook')
global with sharing class PaymentWebhookApi {
  public static final String SIGNATURE_HEADER = 'X-KEM-Signature';

  @HttpPost
  global static void receive() {
    try {
      if (!PaymentLinkService.webhookConfigured()) {
        KemApi.ok(
          503,
          new Map<String, Object>{
            'error' => 'The payment webhook is not configured.'
          }
        );
        return;
      }
      String body = KemApi.body();
      String signature = RestContext.request.headers.get(SIGNATURE_HEADER);
      if (!PaymentLinkService.validSignature(body, signature)) {
        Logger.warn(
          'PaymentWebhookApi',
          'Rejected a payment webhook call with an invalid signature.',
          null
        );
        Logger.flush();
        KemApi.ok(
          401,
          new Map<String, Object>{ 'error' => 'Invalid signature.' }
        );
        return;
      }
      PaymentLinkService.Confirmation note = (PaymentLinkService.Confirmation) JSON.deserialize(
        body,
        PaymentLinkService.Confirmation.class
      );
      BillingService.PaymentResult result = PaymentLinkService.confirm(note);
      KemApi.ok(
        200,
        new Map<String, Object>{
          'paymentId' => result.paymentId,
          'status' => result.status,
          'receiptNumber' => result.receiptNumber,
          'duplicate' => result.duplicate == true
        }
      );
    } catch (Exception e) {
      KemApi.fail(e, 'PaymentWebhookApi.receive');
    }
  }
}
