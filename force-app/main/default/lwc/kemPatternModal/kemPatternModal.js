import { api } from "lwc";
import LightningModal from "lightning/modal";

/** Creates a weekly pattern (CourseOfferingSchedule) for a class. Resolves to the new ID or null. */
export default class KemPatternModal extends LightningModal {
  @api label;
  @api offeringId;
  @api offeringName;
  isSaving = false;

  get defaultDescription() {
    return this.offeringName ? `${this.offeringName} weekly` : "Weekly pattern";
  }

  handleSubmit(event) {
    event.preventDefault();
    this.isSaving = true;
    const fields = {
      ...event.detail.fields,
      CourseOfferingId: this.offeringId
    };
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.close(event.detail.id);
  }

  handleError() {
    this.isSaving = false;
  }

  handleCancel() {
    this.close(null);
  }
}
