import { api } from "lwc";
import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import getSuggestedHolidays from "@salesforce/apex/SiteSetupController.getSuggestedHolidays";
import addHolidays from "@salesforce/apex/SiteSetupController.addHolidays";
import { toHolidayLines, newHoliday, holidayRequest } from "c/kemHolidayLines";
import { reduceErrors } from "c/kemUtils";

/**
 * Adds holidays and breaks to one or more branches: one holiday, or the
 * year's list (Karnataka holidays and usual breaks) to tick and adjust.
 * Resolves to { created, skipped } or null.
 */
export default class KemHolidayModal extends LightningModal {
  @api branchId;
  branchOptions = [];
  selectedBranches = [];
  yearOptions = [];
  year;
  lines = [newHoliday()];
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "Add holidays";
  }

  async connectedCallback() {
    try {
      const choices = await getChoices();
      this.branchOptions = (choices.branches || []).map((b) => ({
        label: b.label,
        value: b.value
      }));
      this.selectedBranches = this.branchId
        ? [this.branchId]
        : this.branchOptions.map((b) => b.value);
      this.year = String(choices.year);
      this.yearOptions = [choices.year, choices.year + 1].map((y) => ({
        label: String(y),
        value: String(y)
      }));
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get cannotSave() {
    return (
      this.isBusy ||
      !this.selectedBranches.length ||
      !holidayRequest(this.lines).length
    );
  }

  get saveLabel() {
    const n = holidayRequest(this.lines).length;
    const b = this.selectedBranches.length;
    return `Add ${n} to ${b} branch${b === 1 ? "" : "es"}`;
  }

  handleBranches(event) {
    this.selectedBranches = event.detail.value;
  }

  handleYear(event) {
    this.year = event.detail.value;
  }

  async handleSuggest() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const suggested = await getSuggestedHolidays({ year: Number(this.year) });
      const own = this.lines.filter((l) => (l.name || "").trim());
      this.lines = [...own, ...toHolidayLines(suggested)];
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleLines(event) {
    this.lines = event.detail.lines;
  }

  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    if (!this.template.querySelector("c-kem-holiday-lines").reportValidity()) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await addHolidays({
        branchIds: this.selectedBranches,
        holidays: holidayRequest(this.lines)
      });
      this.close({ created: result.created, skipped: result.skipped });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
