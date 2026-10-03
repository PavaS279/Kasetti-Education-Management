import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import CURRENCY from "@salesforce/i18n/currency";
import getFinanceDesk from "@salesforce/apex/BillingController.getFinanceDesk";
import confirmPayment from "@salesforce/apex/BillingController.confirmPayment";
import failPayment from "@salesforce/apex/BillingController.failPayment";
import resolveException from "@salesforce/apex/BillingController.resolveException";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const TABS = [
  { value: "pending", label: "Awaiting confirmation" },
  { value: "exceptions", label: "Reconciliation exceptions" },
  { value: "overdue", label: "Overdue invoices" },
  { value: "recent", label: "Recent receipts" }
];

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "—";
}

function daysOverdue(value) {
  const due = new Date(value);
  const today = new Date();
  due.setHours(0, 0, 0, 0);
  today.setHours(0, 0, 0, 0);
  return Math.max(0, Math.round((today - due) / 86400000));
}

export default class KemFinanceDesk extends NavigationMixin(LightningElement) {
  currencyCode = CURRENCY;
  desk;
  errorMessage;
  activeTab = "pending";
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.desk = await getFinanceDesk();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get kpis() {
    return [
      {
        key: "outstanding",
        label: "Outstanding",
        value: this.desk.outstanding,
        className: "kpi kem-card"
      },
      {
        key: "overdue",
        label: `Overdue (${this.desk.overdueCount})`,
        value: this.desk.overdueAmount,
        className: `kpi kem-card${this.desk.overdueCount ? " kpi_alert" : ""}`
      },
      {
        key: "collected",
        label: "Collected this month",
        value: this.desk.collectedThisMonth,
        className: "kpi kem-card kpi_good"
      }
    ];
  }

  get tabs() {
    const counts = {
      pending: this.desk.pending.length,
      exceptions: this.desk.exceptions.length,
      overdue: this.desk.overdue.length,
      recent: this.desk.recent.length
    };
    return TABS.map((t) => ({
      ...t,
      count: counts[t.value],
      selected: t.value === this.activeTab ? "true" : "false",
      className: `tab${t.value === this.activeTab ? " tab_on" : ""}${
        t.value === "exceptions" && counts.exceptions ? " tab_alert" : ""
      }`
    }));
  }

  get showPending() {
    return this.activeTab === "pending";
  }
  get showExceptions() {
    return this.activeTab === "exceptions";
  }
  get showOverdue() {
    return this.activeTab === "overdue";
  }
  get showRecent() {
    return this.activeTab === "recent";
  }

  mapPayment(p) {
    return {
      ...p,
      payer: p.Payer__r?.Name || "—",
      learner: p.Learner__r?.Name,
      invoiceName: p.Student_Invoice__r?.Name,
      dateLabel: formatDate(p.Payment_Date__c)
    };
  }

  get pendingRows() {
    return this.desk.pending.map((p) => this.mapPayment(p));
  }
  get exceptionRows() {
    return this.desk.exceptions.map((p) => this.mapPayment(p));
  }
  get recentRows() {
    return this.desk.recent.map((p) => this.mapPayment(p));
  }
  get overdueRows() {
    return this.desk.overdue.map((i) => {
      const days = daysOverdue(i.Due_Date__c);
      return {
        ...i,
        payer: i.Bill_To__r?.Name || "—",
        learner: i.Learner__r?.Name,
        dueLabel: formatDate(i.Due_Date__c),
        daysLabel: `${days} day${days === 1 ? "" : "s"} overdue`,
        ageClass:
          days > 30
            ? "kem-badge kem-badge_danger"
            : "kem-badge kem-badge_warning"
      };
    });
  }
  get currentEmpty() {
    const list = {
      pending: this.desk.pending,
      exceptions: this.desk.exceptions,
      overdue: this.desk.overdue,
      recent: this.desk.recent
    }[this.activeTab];
    return list.length === 0;
  }
  get emptyMessage() {
    return {
      pending: "No payments are waiting for confirmation.",
      exceptions: "Every confirmed payment is reconciled.",
      overdue: "No invoices are overdue.",
      recent: "No payments received yet."
    }[this.activeTab];
  }

  handleTab(event) {
    this.activeTab = event.currentTarget.dataset.value;
  }

  handleRefresh() {
    this.load();
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

  async run(action, title, message) {
    this.isBusy = true;
    try {
      const result = await action();
      const exception = result?.reconciliationStatus === "Exception";
      toast(
        this,
        title,
        exception
          ? `${result.unallocated} could not be allocated and stays in exceptions.`
          : message,
        exception ? "warning" : "success"
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  handleConfirm(event) {
    const paymentId = event.currentTarget.dataset.id;
    this.run(
      () => confirmPayment({ paymentId }),
      "Payment confirmed",
      "Allocated and receipted."
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
    if (reason) {
      this.run(
        () => failPayment({ paymentId, reason }),
        "Payment marked as failed",
        "Nothing was allocated."
      );
    }
  }

  handleRetry(event) {
    const paymentId = event.currentTarget.dataset.id;
    this.run(
      () => resolveException({ paymentId, note: null }),
      "Payment reconciled",
      "The remaining amount was allocated to open invoices."
    );
  }

  async handleClose(event) {
    const paymentId = event.currentTarget.dataset.id;
    const note = await ReasonModal.open({
      size: "small",
      label: "Close exception",
      message:
        "Open invoices are tried first. Record how any remaining amount was settled (refund, credit note).",
      reasonLabel: "Settlement note",
      confirmLabel: "Reconcile"
    });
    if (note) {
      this.run(
        () => resolveException({ paymentId, note }),
        "Payment reconciled",
        "The exception was closed."
      );
    }
  }
}
