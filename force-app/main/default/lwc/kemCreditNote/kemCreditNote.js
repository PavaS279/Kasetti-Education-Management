import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";
import CURRENCY from "@salesforce/i18n/currency";
import getCreditNote from "@salesforce/apex/CreditController.getCreditNote";
import applyCredit from "@salesforce/apex/CreditController.applyCredit";
import approveRefund from "@salesforce/apex/CreditController.approveRefund";
import rejectRefund from "@salesforce/apex/CreditController.rejectRefund";
import markRefundPaid from "@salesforce/apex/CreditController.markRefundPaid";
import voidCreditNote from "@salesforce/apex/CreditController.voidCreditNote";
import RefundModal from "c/kemRefundModal";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const STATUS_CLASS = {
  Open: "kem-badge kem-badge_info",
  "Partially Used": "kem-badge kem-badge_warning",
  Used: "kem-badge kem-badge_success",
  Void: "kem-badge kem-badge_danger"
};
const REFUND_CLASS = {
  Requested: "kem-badge kem-badge_warning",
  Approved: "kem-badge kem-badge_info",
  Paid: "kem-badge kem-badge_success",
  Rejected: "kem-badge kem-badge_danger"
};
const REFUND_ICON = {
  Requested: "utility:clock",
  Approved: "utility:approval",
  Paid: "utility:check",
  Rejected: "utility:close"
};

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "—";
}

export default class KemCreditNote extends NavigationMixin(LightningElement) {
  @api recordId;
  currencyCode = CURRENCY;
  view;
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.view = await getCreditNote({ creditNoteId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get note() {
    return this.view.creditNote;
  }
  get statusClass() {
    return STATUS_CLASS[this.note.Status__c] || "kem-badge";
  }
  get isVoid() {
    return this.note.Status__c === "Void";
  }
  get amount() {
    return this.note.Amount__c || 0;
  }
  get applied() {
    return this.note.Amount_Applied__c || 0;
  }
  get refunded() {
    return this.note.Amount_Refunded__c || 0;
  }
  get balance() {
    return this.note.Balance__c || 0;
  }
  get usedPercent() {
    return this.amount
      ? Math.min(
          100,
          Math.round(((this.applied + this.refunded) / this.amount) * 100)
        )
      : 0;
  }
  get progressStyle() {
    return `width:${this.usedPercent}%`;
  }
  get progressLabel() {
    return `${this.usedPercent}% used`;
  }
  get issueLabel() {
    return formatDate(this.note.Issue_Date__c);
  }
  get payer() {
    return this.note.Bill_To__r?.Name || "—";
  }
  get learner() {
    return this.note.Learner__r?.Name || "—";
  }
  get className() {
    return this.note.Enrolment__r?.CourseOffering?.Name;
  }
  get source() {
    if (this.note.Source_Invoice__c) {
      return {
        id: this.note.Source_Invoice__c,
        label: this.note.Source_Invoice__r?.Name
      };
    }
    if (this.note.Source_Payment__c) {
      return {
        id: this.note.Source_Payment__c,
        label: this.note.Source_Payment__r?.Name
      };
    }
    return null;
  }
  get hasReserved() {
    return this.view.reserved > 0;
  }
  get canRefund() {
    return this.view.canManage && this.view.available > 0;
  }
  get canVoid() {
    return (
      this.view.canManage &&
      this.note.Status__c === "Open" &&
      this.applied === 0 &&
      this.refunded === 0 &&
      !this.hasReserved
    );
  }
  get hasActions() {
    return this.canRefund || this.canVoid;
  }
  get invoices() {
    const available = this.view.available;
    return this.view.openInvoices.map((i) => ({
      ...i,
      className: i.Enrolment__r?.CourseOffering?.Name,
      dueLabel: formatDate(i.Due_Date__c),
      useAmount: Math.min(available, i.Balance_Due__c || 0),
      applyLabel: `Apply credit to ${i.Name}`
    }));
  }
  get showInvoices() {
    return (
      this.view.canManage && this.view.available > 0 && this.invoices.length > 0
    );
  }
  get applications() {
    return this.view.applications.map((a) => ({
      ...a,
      invoiceName: a.Student_Invoice__r?.Name,
      dateLabel: formatDate(a.Payment_Date__c)
    }));
  }
  get noApplications() {
    return this.view.applications.length === 0;
  }
  get refunds() {
    const me = this.view.currentUserId;
    return this.view.refunds.map((r) => {
      const decidable =
        this.view.canApprove &&
        r.Status__c === "Requested" &&
        r.Requested_By__c !== me;
      return {
        ...r,
        statusClass: REFUND_CLASS[r.Status__c] || "kem-badge",
        icon: REFUND_ICON[r.Status__c] || "utility:moneybag",
        requestedBy: r.Requested_By__r?.Name,
        decidedBy: r.Auto_Approved__c
          ? "auto-approved"
          : r.Approved_By__r?.Name,
        requestedLabel: formatDate(r.CreatedDate),
        paidLabel: formatDate(r.Paid_On__c),
        isPaid: r.Status__c === "Paid",
        isRejected: r.Status__c === "Rejected",
        canDecide: decidable,
        awaitsOther: r.Status__c === "Requested" && !decidable,
        canPay: this.view.canManage && r.Status__c === "Approved"
      };
    });
  }
  get hasRefunds() {
    return this.view.refunds.length > 0;
  }

  async refresh() {
    await this.load();
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
  }

  async run(action, title, message) {
    this.isBusy = true;
    try {
      await action();
      toast(this, title, message);
      await this.refresh();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  async handleApply(event) {
    const invoiceId = event.currentTarget.dataset.id;
    const row = this.invoices.find((i) => i.Id === invoiceId);
    const confirmed = await LightningConfirm.open({
      label: "Use credit",
      message: `Apply ${row.useAmount} of ${this.note.Name} to ${row.Name}?`,
      theme: "info"
    });
    if (!confirmed) {
      return;
    }
    this.run(
      () =>
        applyCredit({ creditNoteId: this.recordId, invoiceId, amount: null }),
      "Credit applied",
      `${row.Name} was paid from the credit.`
    );
  }

  async handleRefund() {
    const refundId = await RefundModal.open({
      size: "small",
      creditNoteId: this.recordId,
      creditNoteName: this.note.Name,
      payerName: this.payer,
      available: this.view.available,
      autoApproveLimit: this.view.autoApproveLimit
    });
    if (!refundId) {
      return;
    }
    toast(
      this,
      "Refund requested",
      "It appears below with its approval status."
    );
    await this.refresh();
  }

  handleApprove(event) {
    const refundId = event.currentTarget.dataset.id;
    this.run(
      () => approveRefund({ refundId }),
      "Refund approved",
      "Finance can now pay it out."
    );
  }

  async handleReject(event) {
    const refundId = event.currentTarget.dataset.id;
    const reason = await ReasonModal.open({
      size: "small",
      label: "Reject refund",
      message: "The amount goes back to the credit balance.",
      confirmLabel: "Reject",
      confirmVariant: "destructive"
    });
    if (reason) {
      this.run(
        () => rejectRefund({ refundId, reason }),
        "Refund rejected",
        "The credit is available again."
      );
    }
  }

  async handlePaid(event) {
    const refundId = event.currentTarget.dataset.id;
    const reference = await ReasonModal.open({
      size: "small",
      label: "Record payout",
      message: "Enter the bank, UPI or cheque reference of the payout.",
      reasonLabel: "Payout reference",
      confirmLabel: "Mark as paid"
    });
    if (reference) {
      this.run(
        () => markRefundPaid({ refundId, reference, paidOn: null }),
        "Refund paid",
        "The credit balance was reduced."
      );
    }
  }

  async handleVoid() {
    const reason = await ReasonModal.open({
      size: "small",
      label: "Void credit note",
      message: "The credit note will no longer be usable.",
      confirmLabel: "Void",
      confirmVariant: "destructive"
    });
    if (reason) {
      this.run(
        () => voidCreditNote({ creditNoteId: this.recordId, reason }),
        "Credit note voided",
        "It can no longer be used."
      );
    }
  }

  handleNavigate(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
