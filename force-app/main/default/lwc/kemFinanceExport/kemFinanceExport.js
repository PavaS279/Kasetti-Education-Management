import { LightningElement } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import getBranches from "@salesforce/apex/FinanceExportController.getBranches";
import getRecent from "@salesforce/apex/FinanceExportController.getRecent";
import preview from "@salesforce/apex/FinanceExportController.preview";
import runExport from "@salesforce/apex/FinanceExportController.runExport";
import { reduceErrors, toast } from "c/kemUtils";

const isoDate = (d) => {
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
};

/** ERP journal export: preview, export to CSV, and earlier exports. */
export default class KemFinanceExport extends LightningElement {
  hidden = false;
  currencyCode = CURRENCY;
  branchOptions = [{ label: "All branches", value: "" }];
  branchId = "";
  fromDate;
  toDate;
  journal;
  recent = [];
  errorMessage;
  isBusy = false;

  connectedCallback() {
    const today = new Date();
    this.fromDate = isoDate(new Date(today.getFullYear(), today.getMonth(), 1));
    this.toDate = isoDate(today);
    this.load();
  }

  async load() {
    try {
      const [branches, recent] = await Promise.all([
        getBranches(),
        getRecent()
      ]);
      this.branchOptions = [{ label: "All branches", value: "" }, ...branches];
      this.recent = recent;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      // Users without finance export access do not see the panel.
      this.hidden =
        message.includes("do not have access") ||
        message.includes("permission");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get request() {
    return {
      fromDate: this.fromDate,
      toDate: this.toDate,
      branchId: this.branchId || null
    };
  }
  get cannotRun() {
    return this.isBusy || !this.fromDate || !this.toDate;
  }
  get accounts() {
    return this.journal ? this.journal.accounts : [];
  }
  get hasAccounts() {
    return this.accounts.length > 0;
  }
  get balanceLabel() {
    return this.journal.balanced ? "Balanced" : "Not balanced";
  }
  get balanceClass() {
    return `kem-badge ${this.journal.balanced ? "kem-badge_success" : "kem-badge_danger"}`;
  }
  get exports() {
    return this.recent.map((e) => ({
      ...e,
      period:
        e.fromDate === e.toDate ? e.fromDate : `${e.fromDate} – ${e.toDate}`,
      scope: e.branchName || "All branches",
      downloadUrl: e.fileId
        ? `/sfc/servlet.shepherd/document/download/${e.fileId}`
        : null
    }));
  }
  get hasExports() {
    return this.recent.length > 0;
  }

  handleFrom(event) {
    this.fromDate = event.target.value;
  }
  handleTo(event) {
    this.toDate = event.target.value;
  }
  handleBranch(event) {
    this.branchId = event.detail.value;
  }

  async handlePreview() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.journal = await preview(this.request);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async handleExport() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const summary = await runExport(this.request);
      toast(
        this,
        `Export ${summary.exportNumber} ready`,
        `${summary.lines} journal lines from ${summary.documents} documents.`
      );
      this.recent = await getRecent();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
