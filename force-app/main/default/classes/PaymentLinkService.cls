/**
 * Online payments in the family portal, gateway-agnostic.
 *
 * A family member starts a payment for an open invoice: a Payment_Link__c
 * with a random token, the balance due, an expiry (Payment_Link_Hours) and,
 * in Live mode, the gateway checkout address built from
 * Payment_Checkout_URL. The gateway (or middleware) confirms the payment by
 * calling the payment webhook with the token, signed with the shared secret
 * (KEM Gateway custom setting); the payment is then recorded through
 * BillingService like any other gateway payment (idempotent on the gateway
 * transaction ID), so allocation, receipts and notices follow.
 *
 * Education Setting Payment_Gateway_Mode: Off (default), Test (no money is
 * taken; finance staff can simulate the gateway confirmation) or Live.
 */
public with sharing class PaymentLinkService {
  public static final String MODE_OFF = 'Off';
  public static final String MODE_TEST = 'Test';
  public static final String MODE_LIVE = 'Live';

  public class LinkView {
    @AuraEnabled
    public Id linkId;
    @AuraEnabled
    public String linkNumber;
    @AuraEnabled
    public String invoiceNumber;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Datetime expiresOn;
    @AuraEnabled
    public String checkoutUrl;
    @AuraEnabled
    public String mode;
    @AuraEnabled
    public String token;
  }

  public class Confirmation {
    public String token;
    public String transactionId;
    public Decimal amount;
    public String status;
  }

  public static String mode() {
    String value = AppSettings.getString('Payment_Gateway_Mode', MODE_OFF);
    return value == MODE_TEST || value == MODE_LIVE ? value : MODE_OFF;
  }

  // ---------------------------------------------------------------- portal

  /** Creates (or reuses) a payment link for an invoice of a learner the portal viewer may see. */
  public static LinkView createForPortal(Id invoiceId) {
    Id viewer = PortalService.viewerContactId();
    Student_Invoice__c invoice = loadInvoice(invoiceId);
    if (
      !PortalService.authorisedLearners(viewer).contains(invoice.Learner__c)
    ) {
      throw new AppException('Invoice not found or not available to you.');
    }
    return create(invoice, viewer, 'Portal');
  }

  /** Staff create a link to send to a family (for example by message). */
  public static LinkView createForStaff(Id invoiceId) {
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    Student_Invoice__c invoice = loadInvoice(invoiceId);
    return create(invoice, invoice.Bill_To__c, 'Staff');
  }

  private static LinkView create(
    Student_Invoice__c invoice,
    Id payerId,
    String via
  ) {
    String currentMode = mode();
    if (currentMode == MODE_OFF) {
      throw new AppException(
        'Online payments are not available yet. Please pay at the branch.'
      );
    }
    if (
      !BillingService.OPEN_STATUSES.contains(invoice.Status__c) ||
      invoice.Balance_Due__c <= 0
    ) {
      throw new AppException(
        'Invoice ' + invoice.Name + ' has nothing left to pay.'
      );
    }
    for (Payment_Link__c existing : [
      SELECT
        Id,
        Name,
        Amount__c,
        Status__c,
        Expires_On__c,
        Checkout_Url__c,
        Token__c
      FROM Payment_Link__c
      WHERE
        Invoice__c = :invoice.Id
        AND Status__c = 'Active'
        AND Amount__c = :invoice.Balance_Due__c
        AND Expires_On__c > :System.now()
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 1
    ]) {
      return view(existing, invoice.Name, currentMode);
    }
    String token = EncodingUtil.convertToHex(Crypto.generateAesKey(256))
      .left(48);
    Payment_Link__c link = new Payment_Link__c(
      Invoice__c = invoice.Id,
      Payer__c = payerId,
      Branch__c = invoice.Branch__c,
      Amount__c = invoice.Balance_Due__c,
      Token__c = token,
      Status__c = 'Active',
      Expires_On__c = System.now()
        .addHours(AppSettings.getInteger('Payment_Link_Hours', 24)),
      Created_Via__c = via
    );
    if (currentMode == MODE_LIVE) {
      link.Checkout_Url__c = checkoutUrl(
        token,
        invoice.Balance_Due__c,
        invoice.Name
      );
    }
    new Writer().insertLink(link);
    return view(load(link.Id), invoice.Name, currentMode);
  }

  @TestVisible
  private static String checkoutUrl(
    String token,
    Decimal amount,
    String invoiceNumber
  ) {
    String template = AppSettings.getString('Payment_Checkout_URL', '');
    if (String.isBlank(template) || !template.startsWith('https://')) {
      throw new AppException(
        'The payment gateway checkout address is not configured.'
      );
    }
    return template
      .replace('{token}', EncodingUtil.urlEncode(token, 'UTF-8'))
      .replace('{amount}', amount.setScale(2).toPlainString())
      .replace('{invoice}', EncodingUtil.urlEncode(invoiceNumber, 'UTF-8'))
      .replace('{currency}', UserInfo.getDefaultCurrency());
  }

  // ---------------------------------------------------------------- confirmation

  /**
   * Confirms (or fails) a payment link. Called by the signed webhook, or by
   * finance staff in Test mode. Returns the payment result.
   */
  public static BillingService.PaymentResult confirm(Confirmation note) {
    if (note == null || String.isBlank(note.token)) {
      throw new AppException('token is required.');
    }
    if (String.isBlank(note.transactionId)) {
      throw new AppException('transactionId is required.');
    }
    String status = String.isBlank(note.status)
      ? 'success'
      : note.status.toLowerCase();
    List<Payment_Link__c> links = [
      SELECT
        Id,
        Name,
        Invoice__c,
        Payer__c,
        Amount__c,
        Status__c,
        Expires_On__c,
        Payment__c,
        Token__c
      FROM Payment_Link__c
      WHERE Token__c = :note.token
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (links.isEmpty()) {
      throw new AppException('Unknown payment link.');
    }
    Payment_Link__c link = links[0];
    if (status == 'failed') {
      if (link.Status__c == 'Active') {
        new Writer()
          .updateLink(
            new Payment_Link__c(
              Id = link.Id,
              Status__c = 'Failed',
              Gateway_Reference__c = note.transactionId.left(100)
            )
          );
      }
      BillingService.PaymentResult failed = new BillingService.PaymentResult();
      failed.status = 'Failed';
      failed.duplicate = false;
      return failed;
    }
    if (status != 'success') {
      throw new AppException('status must be success or failed.');
    }
    if (link.Status__c == 'Paid' && link.Payment__c != null) {
      // A repeated confirmation: the same payment again.
      BillingService.PaymentResult again = new BillingService.PaymentResult();
      again.paymentId = link.Payment__c;
      again.status = 'Confirmed';
      again.duplicate = true;
      return again;
    }
    if (link.Status__c == 'Cancelled') {
      throw new AppException('The payment link was cancelled.');
    }
    Decimal amount = note.amount == null ? link.Amount__c : note.amount;
    if (amount <= 0 || amount > link.Amount__c) {
      throw new AppException(
        'amount must be more than zero and at most ' +
          link.Amount__c.setScale(2) +
          '.'
      );
    }
    // A late confirmation of an expired link is still recorded: the money was taken.
    BillingService.PaymentRequest request = new BillingService.PaymentRequest();
    request.invoiceId = link.Invoice__c;
    request.payerContactId = link.Payer__c;
    request.amount = amount;
    request.method = 'Online Gateway';
    request.gatewayTransactionId = note.transactionId;
    request.reference = link.Name;
    request.confirmed = true;
    BillingService.PaymentResult result = new Writer().recordPayment(request);
    new Writer()
      .updateLink(
        new Payment_Link__c(
          Id = link.Id,
          Status__c = 'Paid',
          Payment__c = result.paymentId,
          Gateway_Reference__c = note.transactionId.left(100)
        )
      );
    return result;
  }

  /** Test mode only: finance staff simulate the gateway's confirmation of a link. */
  public static BillingService.PaymentResult simulate(Id linkId) {
    if (mode() != MODE_TEST) {
      throw new AppException(
        'Simulated payments are only possible in Test mode.'
      );
    }
    RecordAccess.assertPermission(BillingService.MANAGE_PERMISSION);
    Payment_Link__c link = load(linkId);
    Confirmation note = new Confirmation();
    note.token = link.Token__c;
    note.transactionId = 'TEST-' + link.Name;
    note.status = 'success';
    return confirm(note);
  }

  // ---------------------------------------------------------------- signature

  /** True when the hex HMAC-SHA256 of the body with the configured secret equals the signature. */
  public static Boolean validSignature(String body, String signature) {
    String secret = webhookSecret();
    if (String.isBlank(secret) || String.isBlank(signature)) {
      return false;
    }
    String expected = EncodingUtil.convertToHex(
      Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(body == null ? '' : body),
        Blob.valueOf(secret)
      )
    );
    return constantTimeEquals(expected, signature.trim().toLowerCase());
  }

  public static Boolean webhookConfigured() {
    return String.isNotBlank(webhookSecret());
  }

  @TestVisible
  private static String secretOverride;

  private static String webhookSecret() {
    if (Test.isRunningTest() && secretOverride != null) {
      return secretOverride;
    }
    KEM_Gateway__c settings = KEM_Gateway__c.getOrgDefaults();
    return settings == null ? null : settings.Webhook_Secret__c;
  }

  private static Boolean constantTimeEquals(String a, String b) {
    if (a.length() != b.length()) {
      return false;
    }
    Integer diff = 0;
    for (Integer i = 0; i < a.length(); i++) {
      diff |= a.charAt(i) ^ b.charAt(i);
    }
    return diff == 0;
  }

  // ---------------------------------------------------------------- housekeeping

  /** Marks active links past their expiry as Expired (hourly). */
  public static Integer expireLinks() {
    List<Payment_Link__c> updates = new List<Payment_Link__c>();
    for (Payment_Link__c link : [
      SELECT Id
      FROM Payment_Link__c
      WHERE Status__c = 'Active' AND Expires_On__c < :System.now()
      WITH SYSTEM_MODE
      LIMIT 2000
    ]) {
      updates.add(new Payment_Link__c(Id = link.Id, Status__c = 'Expired'));
    }
    new Writer().updateLinks(updates);
    return updates.size();
  }

  // ---------------------------------------------------------------- helpers

  private static Student_Invoice__c loadInvoice(Id invoiceId) {
    List<Student_Invoice__c> rows = [
      SELECT
        Id,
        Name,
        Status__c,
        Balance_Due__c,
        Learner__c,
        Bill_To__c,
        Branch__c
      FROM Student_Invoice__c
      WHERE Id = :invoiceId
      WITH SYSTEM_MODE
    ];
    if (rows.isEmpty()) {
      throw new AppException('Invoice not found or not available to you.');
    }
    return rows[0];
  }

  private static Payment_Link__c load(Id linkId) {
    return [
      SELECT
        Id,
        Name,
        Amount__c,
        Status__c,
        Expires_On__c,
        Checkout_Url__c,
        Token__c,
        Invoice__r.Name
      FROM Payment_Link__c
      WHERE Id = :linkId
      WITH SYSTEM_MODE
    ];
  }

  private static LinkView view(
    Payment_Link__c link,
    String invoiceNumber,
    String currentMode
  ) {
    LinkView v = new LinkView();
    v.linkId = link.Id;
    v.linkNumber = link.Name;
    v.invoiceNumber = invoiceNumber;
    v.amount = link.Amount__c;
    v.status = link.Status__c;
    v.expiresOn = link.Expires_On__c;
    v.checkoutUrl = link.Checkout_Url__c;
    v.mode = currentMode;
    // The token is only given out for the gateway hand-off in Live mode.
    v.token = currentMode == MODE_LIVE ? link.Token__c : null;
    return v;
  }

  /**
   * Links are system-managed: portal users and the webhook's integration user
   * only start or confirm them through this service. Recording the payment
   * also runs in system mode, because a portal user or the gateway cannot
   * create payments themselves; the link (created for an authorised viewer)
   * is the authorisation.
   */
  private without sharing class Writer {
    void insertLink(Payment_Link__c link) {
      Database.insert(link, AccessLevel.SYSTEM_MODE);
    }
    void updateLink(Payment_Link__c link) {
      Database.update(link, AccessLevel.SYSTEM_MODE);
    }
    void updateLinks(List<Payment_Link__c> links) {
      Database.update(links, AccessLevel.SYSTEM_MODE);
    }
    BillingService.PaymentResult recordPayment(
      BillingService.PaymentRequest request
    ) {
      return BillingService.recordPayment(request);
    }
  }
}
