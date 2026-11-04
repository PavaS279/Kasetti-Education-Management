import LightningModal from "lightning/modal";
import createFaculty from "@salesforce/apex/CatalogSetupController.createFaculty";
import { reduceErrors } from "c/kemUtils";

/** Adds a faculty member (a teacher shown on classes). Resolves to the contact Id, or null. */
export default class KemFacultyModal extends LightningModal {
  firstName = "";
  lastName = "";
  email = "";
  phone = "";
  subject = "";
  errorMessage;
  isBusy = false;

  get heading() {
    return "New faculty member";
  }

  get cannotSubmit() {
    return this.isBusy || !this.lastName.trim();
  }

  handleField(event) {
    this[event.target.dataset.field] = event.target.value || "";
  }

  handleCancel() {
    this.close(null);
  }

  async handleSubmit() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    if (!inputs.every((i) => i.reportValidity())) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const id = await createFaculty({
        request: {
          firstName: this.firstName.trim(),
          lastName: this.lastName.trim(),
          email: this.email.trim(),
          phone: this.phone.trim(),
          subject: this.subject.trim()
        }
      });
      this.close(id);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
