import { LightningElement } from "lwc";
import getDues from "@salesforce/apex/CollegeAdmissionsController.getDues";

const money = (value) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(value || 0);

const inr = { currencyCode: "INR" };
const COLUMNS = [
  { label: "Campus", fieldName: "campus" },
  { label: "Programme", fieldName: "programme" },
  { label: "Branch", fieldName: "branch" },
  { label: "Year", fieldName: "academicYear", initialWidth: 90 },
  {
    label: "Billed",
    fieldName: "billed",
    type: "currency",
    typeAttributes: inr
  },
  { label: "Paid", fieldName: "paid", type: "currency", typeAttributes: inr },
  { label: "Due", fieldName: "due", type: "currency", typeAttributes: inr },
  {
    label: "Awaiting clearance",
    fieldName: "awaitingClearance",
    type: "currency",
    typeAttributes: inr
  },
  { label: "Expiring soon", fieldName: "expiringSoon", type: "number" },
  { label: "Fee holds", fieldName: "feeHolds", type: "number" }
];

/** Finance Desk "College dues"; renders nothing when there are no college invoices. */
export default class KemCollegeDues extends LightningElement {
  columns = COLUMNS;
  rows = [];
  totals;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      const result = await getDues();
      this.rows = result.rows || [];
      this.totals = result.total;
      this.errorMessage = undefined;
    } catch (error) {
      this.rows = [];
      this.errorMessage =
        error?.body?.message || "College dues could not be loaded.";
    }
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get total() {
    const t = this.totals || {};
    return {
      billed: money(t.billed),
      paid: money(t.paid),
      due: money(t.due),
      awaitingClearance: money(t.awaitingClearance),
      expiringSoon: t.expiringSoon || 0,
      feeHolds: t.feeHolds || 0
    };
  }
}
