import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import CURRENCY from "@salesforce/i18n/currency";
import getInvoice from "@salesforce/apex/BillingController.getInvoice";
import issueInvoice from "@salesforce/apex/BillingController.issueInvoice";
import cancelInvoice from "@salesforce/apex/BillingController.cancelInvoice";
import confirmPayment from "@salesforce/apex/BillingController.confirmPayment";
import failPayment from "@salesforce/apex/BillingController.failPayment";
import PaymentModal from "c/kemPaymentModal";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const STATUS_CLASS = {
  Draft: "kem-badge",
  Issued: "kem-badge kem-badge_info",
  "Partially Paid": "kem-badge kem-badge_warning",
  Paid: "kem-badge kem-badge_success",
  Cancelled: "kem-badge kem-badge_danger"
};

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "—";
}

export default class KemInvoice extends NavigationMixin(LightningElement) {
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
      this.view = await getInvoice({ invoiceId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get invoice() {
    return this.view.invoice;
  }
  get status() {
    return this.invoice.Status__c;
  }
  get statusClass() {
    return STATUS_CLASS[this.status] || "kem-badge";
  }
  get isOverdue() {
    return this.invoice.Overdue__c;
  }
  get billTo() {
    return this.invoice.Bill_To__r?.Name || "—";
  }
  get billToEmail() {
    return this.invoice.Bill_To__r?.Email || "";
  }
  get learnerName() {
    return this.invoice.Learner__r?.Name || "—";
  }
  get className() {
    return this.invoice.Enrolment__r?.CourseOffering?.Name || "—";
  }
  get branchName() {
    return this.invoice.Branch__r?.Name || "—";
  }
  get issueLabel() {
    return formatDate(this.invoice.Issue_Date__c);
  }
  get dueLabel() {
    return formatDate(this.invoice.Due_Date__c);
  }
  get total() {
    return this.invoice.Total__c || 0;
  }
  get paid() {
    return this.invoice.Amount_Paid__c || 0;
  }
  get balance() {
    return this.invoice.Balance_Due__c || 0;
  }
  get paidPercent() {
    return this.total
      ? Math.min(100, Math.round((this.paid / this.total) * 100))
      : 0;
  }
  get progressStyle() {
    return `width:${this.paidPercent}%`;
  }
  get progressLabel() {
    return `${this.paidPercent}% paid`;
  }
  get canIssue() {
    return this.view.canManage && this.status === "Draft";
  }
  get canPay() {
    return (
      this.view.canManage && ["Issued", "Partially Paid"].includes(this.status)
    );
  }
  get canCancel() {
    return (
      this.view.canManage &&
      ["Draft", "Issued"].includes(this.status) &&
      this.paid === 0
    );
  }
  get hasActions() {
    return this.canIssue || this.canPay || this.canCancel;
  }
  get isCancelled() {
    return this.status === "Cancelled";
  }
  get lines() {
    return this.view.lines.map((l) => ({
      ...l,
      label: l.Description__c || l.Fee_Type__c,
      hasDiscount: l.Discount_Amount__c > 0
    }));
  }
  get payments() {
    return this.view.allocations.map((a) => ({
      ...a,
      paymentName: a.Student_Payment__r?.Name,
      receipt: a.Student_Payment__r?.Receipt_Number__c,
      method: a.Student_Payment__r?.Method__c,
      reference: a.Student_Payment__r?.Reference__c,
      dateLabel: formatDate(a.Student_Payment__r?.Payment_Date__c)
    }));
  }
  get noPayments() {
    return this.view.allocations.length === 0;
  }
  get pending() {
    return this.view.pendingPayments.map((p) => ({
      ...p,
      dateLabel: formatDate(p.Payment_Date__c),
      confirmLabel: `Confirm ${p.Name}`,
      failLabel: `Mark ${p.Name} as failed`
    }));
  }
  get hasPending() {
    return this.view.pendingPayments.length > 0;
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

  handleIssue() {
    this.run(
      () => issueInvoice({ invoiceId: this.recordId }),
      "Invoice issued",
      "The due date was set from the branch policy."
    );
  }

  async handlePay() {
    const result = await PaymentModal.open({
      size: "small",
      invoiceId: this.recordId,
      invoiceNumber: this.invoice.Name,
      payerName: this.billTo,
      balance: this.balance
    });
    if (!result) {
      return;
    }
    let message = `Receipt ${result.receiptNumber} issued.`;
    if (result.status === "Pending") {
      message = "Recorded as pending. Confirm it once the funds clear.";
    } else if (result.reconciliationStatus === "Exception") {
      message = `Receipt ${result.receiptNumber}. ${result.unallocated} could not be allocated and is flagged for reconciliation.`;
    }
    toast(
      this,
      "Payment recorded",
      message,
      result.reconciliationStatus === "Exception" ? "warning" : "success"
    );
    await this.refresh();
  }

  async handleCancel() {
    const reason = await ReasonModal.open({
      size: "small",
      label: "Cancel invoice",
      message:
        "The fee lines are released so the enrolment can be invoiced again.",
      confirmLabel: "Cancel invoice",
      confirmVariant: "destructive"
    });
    if (!reason) {
      return;
    }
    this.run(
      () => cancelInvoice({ invoiceId: this.recordId, reason }),
      "Invoice cancelled",
      "The enrolment can be invoiced again."
    );
  }

  handleConfirm(event) {
    const paymentId = event.currentTarget.dataset.id;
    this.run(
      () => confirmPayment({ paymentId }),
      "Payment confirmed",
      "The payment was allocated and a receipt issued."
    );
  }

  async handleFail(event) {
    const paymentId = event.currentTarget.dataset.id;
    const reason = await ReasonModal.open({
      size: "small",
      label: "Payment failed",
      message: "The payment is closed without being allocated.",
      confirmLabel: "Mark as failed",
      confirmVariant: "destructive"
    });
    if (!reason) {
      return;
    }
    this.run(
      () => failPayment({ paymentId, reason }),
      "Payment marked as failed",
      "Nothing was allocated."
    );
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
