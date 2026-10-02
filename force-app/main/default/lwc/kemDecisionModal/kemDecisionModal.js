import { api } from "lwc";
import LightningModal from "lightning/modal";

const CHOICES = [
  {
    value: "Admit",
    label: "Admit",
    hint: "Make an offer",
    icon: "utility:success"
  },
  {
    value: "Waitlist",
    label: "Waitlist",
    hint: "Hold for a seat",
    icon: "utility:clock"
  },
  {
    value: "Reject",
    label: "Reject",
    hint: "Close the application",
    icon: "utility:ban"
  }
];

/** Resolves to { decision, reason, validDays } or null. */
export default class KemDecisionModal extends LightningModal {
  @api label;
  @api defaultValidDays = 14;
  decision = "Admit";
  reason = "";
  validDays;

  connectedCallback() {
    this.validDays = this.defaultValidDays;
  }

  get choices() {
    return CHOICES.map((c) => ({
      ...c,
      checked: c.value === this.decision ? "true" : "false",
      className: `choice choice_${c.value.toLowerCase()}${c.value === this.decision ? " choice_selected" : ""}`
    }));
  }
  get isAdmit() {
    return this.decision === "Admit";
  }
  get isReasonRequired() {
    return !this.isAdmit;
  }
  get reasonLabel() {
    return this.isAdmit ? "Note (optional)" : "Reason";
  }
  get isInvalid() {
    return this.isReasonRequired && !this.reason.trim();
  }

  handleChoice(event) {
    this.decision = event.currentTarget.dataset.value;
  }
  handleReason(event) {
    this.reason = event.target.value;
  }
  handleDays(event) {
    this.validDays = parseInt(event.target.value, 10);
  }
  handleCancel() {
    this.close(null);
  }
  handleConfirm() {
    this.close({
      decision: this.decision,
      reason: this.reason.trim(),
      validDays: this.validDays
    });
  }
}
