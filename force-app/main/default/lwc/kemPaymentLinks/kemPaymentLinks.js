import { LightningElement, api } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import getPanel from "@salesforce/apex/PaymentLinkController.getPanel";
import createLink from "@salesforce/apex/PaymentLinkController.createLink";
import simulate from "@salesforce/apex/PaymentLinkController.simulate";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const STATUS_CLASS = {
  Active: "kem-badge kem-badge_warning",
  Paid: "kem-badge kem-badge_success",
  Failed: "kem-badge kem-badge_danger"
};

/** Online payment links of an invoice (finance staff). */
export default class KemPaymentLinks extends LightningElement {
  @api recordId;
  panel;
  errorMessage;
  hidden = false;
  isBusy = false;
  checkoutUrl;
  currencyCode = CURRENCY;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.panel = await getPanel({ invoiceId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get isOff() {
    return this.panel?.mode === "Off";
  }
  get isTest() {
    return this.panel?.mode === "Test";
  }
  get modeLabel() {
    return this.isOff
      ? "Online payments off"
      : `Gateway: ${this.panel.mode} mode`;
  }
  get webhookWarning() {
    return this.panel?.mode === "Live" && !this.panel.webhookConfigured;
  }
  get links() {
    return (this.panel?.links || []).map((l) => ({
      ...l,
      statusClass: STATUS_CLASS[l.Status__c] || "kem-badge",
      canSimulate: this.isTest && l.Status__c === "Active"
    }));
  }
  get hasLinks() {
    return this.links.length > 0;
  }

  async handleCreate() {
    this.isBusy = true;
    try {
      const link = await createLink({ invoiceId: this.recordId });
      this.checkoutUrl = link.checkoutUrl;
      toast(
        this,
        "Payment link ready",
        `${link.linkNumber} for the balance due.`
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not create the payment link");
    } finally {
      this.isBusy = false;
    }
  }

  async handleSimulate(event) {
    this.isBusy = true;
    try {
      await simulate({ linkId: event.currentTarget.dataset.id });
      toast(
        this,
        "Payment recorded",
        "The test payment was confirmed and allocated."
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not simulate the payment");
    } finally {
      this.isBusy = false;
    }
  }
}
