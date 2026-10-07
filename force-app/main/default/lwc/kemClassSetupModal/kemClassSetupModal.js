import { api } from "lwc";
import LightningModal from "lightning/modal";

/** Class set-up in a modal (from the Set-up Centre gaps). Resolves to { updated, message } or null. */
export default class KemClassSetupModal extends LightningModal {
  @api classId;
  @api className;

  get heading() {
    return this.className ? `Set up ${this.className}` : "Class set-up";
  }

  handleSaved(event) {
    this.close(event.detail);
  }

  handleCancel() {
    this.close(null);
  }
}
