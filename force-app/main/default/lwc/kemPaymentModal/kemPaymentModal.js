import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import recordPayment from "@salesforce/apex/BillingController.recordPayment";
import { reduceErrors } from "c/kemUtils";

const METHODS = [
  "Cash",
  "UPI",
  "Card",
  "Bank Transfer",
  "Cheque",
  "Online Gateway"
];
const CLEARS_LATER = ["Cheque", "Bank Transfer"];

/** Records a payment against an invoice. Resolves to the PaymentResult, or null when cancelled. */
export default class KemPaymentModal extends LightningModal {
  @api invoiceId;
  @api invoiceNumber;
  @api payerName;
  @api balance;
  currencyCode = CURRENCY;
  amount;
  method = "Cash";
  reference = "";
  paymentDate = new Date().toISOString().slice(0, 10);
  cleared = true;
  errorMessage;
  isSaving = false;

  connectedCallback() {
    this.amount = this.balance;
  }

  get heading() {
    return `Record payment · ${this.invoiceNumber}`;
  }
  get methodOptions() {
    return METHODS.map((m) => ({ label: m, value: m }));
  }
  get needsReference() {
    return this.method !== "Cash";
  }
  get isOverpayment() {
    return Number(this.amount) > Number(this.balance);
  }
  get clearedHelp() {
    return this.cleared
      ? "The payment is confirmed now and allocated to the invoice."
      : "The payment is recorded as pending and allocated when you confirm it.";
  }

  handleAmount(event) {
    this.amount = event.target.value;
  }
  handleMethod(event) {
    this.method = event.detail.value;
    this.cleared = !CLEARS_LATER.includes(this.method);
  }
  handleReference(event) {
    this.reference = event.target.value;
  }
  handleDate(event) {
    this.paymentDate = event.target.value;
  }
  handleCleared(event) {
    this.cleared = event.target.checked;
  }
  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    if (!inputs.reduce((ok, input) => input.reportValidity() && ok, true)) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const result = await recordPayment({
        request: {
          invoiceId: this.invoiceId,
          amount: Number(this.amount),
          method: this.method,
          reference: this.reference || null,
          paymentDate: this.paymentDate,
          confirmed: this.cleared
        }
      });
      this.close(result);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isSaving = false;
    }
  }
}
