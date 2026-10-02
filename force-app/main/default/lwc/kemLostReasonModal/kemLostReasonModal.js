import { api } from "lwc";
import LightningModal from "lightning/modal";

const REASONS = [
  "Price",
  "Schedule",
  "Location",
  "Chose Competitor",
  "Not Interested",
  "Unreachable",
  "Duplicate",
  "Other"
];

export default class KemLostReasonModal extends LightningModal {
  @api label;
  reason;

  get options() {
    return REASONS.map((r) => ({ label: r, value: r }));
  }

  get isInvalid() {
    return !this.reason;
  }

  handleChange(event) {
    this.reason = event.detail.value;
  }

  handleCancel() {
    this.close(null);
  }

  handleConfirm() {
    this.close(this.reason);
  }
}
