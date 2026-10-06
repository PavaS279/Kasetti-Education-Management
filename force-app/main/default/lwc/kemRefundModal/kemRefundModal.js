import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import requestRefund from "@salesforce/apex/CreditController.requestRefund";
import { reduceErrors } from "c/kemUtils";

const METHODS = [
  "Bank Transfer",
  "UPI",
  "Cash",
  "Cheque",
  "Card Reversal",
  "Online Gateway"
].map((m) => ({ label: m, value: m }));

/** Requests a refund of credit. Resolves to the refund Id, or null when cancelled. */
export default class KemRefundModal extends LightningModal {
  @api creditNoteId;
  @api creditNoteName;
  @api payerName;
  @api available = 0;
  @api autoApproveLimit = 0;
  currencyCode = CURRENCY;
  methodOptions = METHODS;
  amount;
  method = "Bank Transfer";
  reason = "";
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.amount = this.available;
  }

  get heading() {
    return `Refund from ${this.creditNoteName}`;
  }
  get needsApproval() {
    return Number(this.amount) > Number(this.autoApproveLimit);
  }
  get approvalNote() {
    return this.needsApproval
      ? "Above the auto-approval limit: an approver other than you must approve it before it is paid."
      : "Within the auto-approval limit: approved immediately, ready to pay out.";
  }
  get approvalClass() {
    return `note ${this.needsApproval ? "note_warn" : "note_ok"}`;
  }
  get cannotSubmit() {
    const value = Number(this.amount);
    return (
      this.isBusy ||
      !value ||
      value <= 0 ||
      value > Number(this.available) ||
      !this.method ||
      !this.reason.trim()
    );
  }

  handleAmount(event) {
    this.amount = event.target.value;
  }
  handleMethod(event) {
    this.method = event.detail.value;
  }
  handleReason(event) {
    this.reason = event.target.value || "";
  }
  handleCancel() {
    this.close(null);
  }

  async handleSubmit() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const refundId = await requestRefund({
        request: {
          creditNoteId: this.creditNoteId,
          amount: Number(this.amount),
          method: this.method,
          reason: this.reason.trim()
        }
      });
      this.close(refundId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
