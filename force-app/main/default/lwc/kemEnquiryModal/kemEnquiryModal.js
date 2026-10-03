import { api } from "lwc";
import LightningModal from "lightning/modal";
import { reduceErrors } from "c/kemUtils";

/**
 * Admissions enquiry form: learner, guardian and interest in one step.
 * Replaces the standard Lead form, whose Company field does not apply to
 * education enquiries. Resolves to the new enquiry Id, or null when cancelled.
 */
export default class KemEnquiryModal extends LightningModal {
  @api branchId;
  errorMessage;
  isSaving = false;

  handleSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields };
    const hasContact = [
      "Email",
      "MobilePhone",
      "Guardian_Email__c",
      "Guardian_Phone__c"
    ].some((name) => fields[name]);
    if (!hasContact) {
      this.errorMessage =
        "Enter at least one email address or phone number for the learner or guardian.";
      return;
    }
    if (!fields.Enquiry_Channel__c) {
      fields.Enquiry_Channel__c = "Walk-in";
    }
    this.errorMessage = undefined;
    this.isSaving = true;
    this.refs.form.submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.close(event.detail.id);
  }

  handleError(event) {
    this.isSaving = false;
    this.errorMessage =
      event.detail?.detail ||
      event.detail?.message ||
      reduceErrors(event.detail).join(" ");
  }

  handleCancel() {
    this.close(null);
  }

  handleSave() {
    this.refs.submit.click();
  }
}
