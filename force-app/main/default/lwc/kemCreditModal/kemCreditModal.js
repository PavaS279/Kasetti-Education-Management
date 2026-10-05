import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import issueCreditNote from "@salesforce/apex/CreditController.issueCreditNote";
import { reduceErrors } from "c/kemUtils";

const ORIGINS = [
  { label: "Withdrawal (learner leaving)", value: "Withdrawal" },
  { label: "Goodwill", value: "Goodwill" },
  { label: "Other", value: "Other" }
];

/** Issues a credit note against money paid on an invoice. Resolves to its Id, or null. */
export default class KemCreditModal extends LightningModal {
  @api invoiceId;
  @api invoiceNumber;
  @api paid = 0;
  currencyCode = CURRENCY;
  originOptions = ORIGINS;
  amount;
  origin = "Withdrawal";
  reason = "";
  errorMessage;
  isBusy = false;

  get label() {
    return `Credit note for ${this.invoiceNumber}`;
  }
  get cannotSubmit() {
    const value = Number(this.amount);
    return (
      this.isBusy ||
      !value ||
      value <= 0 ||
      value > Number(this.paid) ||
      !this.reason.trim()
    );
  }

  handleAmount(event) {
    this.amount = event.target.value;
  }
  handleOrigin(event) {
    this.origin = event.detail.value;
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
      const creditNoteId = await issueCreditNote({
        request: {
          sourceInvoiceId: this.invoiceId,
          amount: Number(this.amount),
          origin: this.origin,
          reason: this.reason.trim()
        }
      });
      this.close(creditNoteId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
