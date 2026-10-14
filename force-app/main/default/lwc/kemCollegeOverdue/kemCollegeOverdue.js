import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getOverdue from "@salesforce/apex/CollegeAdmissionsController.getOverdue";
import extendPayment from "@salesforce/apex/CollegeAdmissionsController.extendPayment";
import cancelAdmission from "@salesforce/apex/CollegeAdmissionsController.cancelAdmission";

/** The Dean's list of overdue provisional admissions with extend and cancel actions. */
export default class KemCollegeOverdue extends LightningElement {
  rows = [];
  loaded = false;
  visible = false;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      const rows = await getOverdue();
      this.visible = rows !== null && rows !== undefined;
      this.rows = rows || [];
      this.errorMessage = undefined;
    } catch (error) {
      this.rows = [];
      this.visible = true;
      this.errorMessage =
        error?.body?.message || "Overdue admissions could not be loaded.";
    }
    this.loaded = true;
  }

  get hasRows() {
    return Boolean(this.rows && this.rows.length);
  }

  value(id, field) {
    const input = this.template.querySelector(
      `lightning-input[data-id="${id}"][data-field="${field}"]`
    );
    return input ? input.value : undefined;
  }

  handleExtend(event) {
    const id = event.target.dataset.id;
    return this.run(
      () =>
        extendPayment({
          enrolmentId: id,
          newDueBy: this.value(id, "date"),
          reason: this.value(id, "reason")
        }),
      "Payment date extended"
    );
  }

  handleCancel(event) {
    const id = event.target.dataset.id;
    return this.run(
      () =>
        cancelAdmission({ enrolmentId: id, reason: this.value(id, "reason") }),
      "Admission cancelled"
    );
  }

  async run(action, success) {
    try {
      await action();
      this.dispatchEvent(
        new ShowToastEvent({ title: success, variant: "success" })
      );
      await this.load();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Not saved",
          message: error?.body?.message,
          variant: "error"
        })
      );
    }
  }
}
