import { api } from "lwc";
import LightningModal from "lightning/modal";

export default class KemPriceModal extends LightningModal {
  @api label;
  @api courseId;
  isSaving = false;

  get today() {
    return new Date().toISOString().slice(0, 10);
  }

  handleSubmit(event) {
    event.preventDefault();
    this.isSaving = true;
    const fields = {
      ...event.detail.fields,
      Learning_Course__c: this.courseId
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
