import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import previewInstalmentPlan from "@salesforce/apex/BillingController.previewInstalmentPlan";
import createInstalmentPlan from "@salesforce/apex/BillingController.createInstalmentPlan";
import { reduceErrors } from "c/kemUtils";

const COUNT_OPTIONS = Array.from({ length: 11 }, (_, i) => ({
  label: `${i + 2} instalments`,
  value: String(i + 2)
}));
const INTERVAL_OPTIONS = [
  { label: "Every month", value: "1" },
  { label: "Every 2 months", value: "2" },
  { label: "Every 3 months", value: "3" },
  { label: "Every 6 months", value: "6" }
];

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "";
}

/** Splits an issued invoice into instalments. Resolves to true when a plan was saved. */
export default class KemInstalmentModal extends LightningModal {
  @api invoiceId;
  @api invoiceNumber;
  @api total;
  @api dueDate;
  currencyCode = CURRENCY;
  countOptions = COUNT_OPTIONS;
  intervalOptions = INTERVAL_OPTIONS;
  count = "3";
  interval = "1";
  firstDueDate;
  plan = [];
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.firstDueDate = this.dueDate || new Date().toISOString().slice(0, 10);
    this.loadPreview();
  }

  get heading() {
    return `Instalment plan · ${this.invoiceNumber}`;
  }
  get rows() {
    return this.plan.map((p) => ({
      ...p,
      key: String(p.sequence),
      dueLabel: formatDate(p.dueDate)
    }));
  }
  get hasPlan() {
    return this.plan.length > 0;
  }
  get cannotSave() {
    return this.isBusy || !this.hasPlan;
  }

  request() {
    return {
      invoiceId: this.invoiceId,
      count: Number(this.count),
      firstDueDate: this.firstDueDate,
      intervalMonths: Number(this.interval)
    };
  }

  async loadPreview() {
    this.errorMessage = undefined;
    try {
      this.plan = await previewInstalmentPlan({ request: this.request() });
    } catch (error) {
      this.plan = [];
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  handleCount(event) {
    this.count = event.detail.value;
    this.loadPreview();
  }
  handleInterval(event) {
    this.interval = event.detail.value;
    this.loadPreview();
  }
  handleDate(event) {
    this.firstDueDate = event.target.value;
    this.loadPreview();
  }
  handleCancel() {
    this.close(false);
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await createInstalmentPlan({ request: this.request() });
      this.close(true);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
