import { api } from "lwc";
import LightningModal from "lightning/modal";

/** Generic "confirm with a reason" modal. Resolves to the reason, or null when cancelled. */
export default class KemReasonModal extends LightningModal {
  @api label;
  @api message;
  @api reasonLabel = "Reason";
  @api confirmLabel = "Confirm";
  @api confirmVariant = "brand";
  reason = "";

  get isInvalid() {
    return !this.reason || !this.reason.trim();
  }

  handleChange(event) {
    this.reason = event.target.value;
  }

  handleCancel() {
    this.close(null);
  }

  handleConfirm() {
    this.close(this.reason.trim());
  }
}
