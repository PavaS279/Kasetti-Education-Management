import { api } from "lwc";
import LightningModal from "lightning/modal";
import sendMessage from "@salesforce/apex/MessageController.sendMessage";
import { reduceErrors } from "c/kemUtils";

const CHANNELS = [
  { label: "Email and portal", value: "Both" },
  { label: "Email only", value: "Email" },
  { label: "Portal only", value: "Portal" }
];

/** Composes a staff message to the learner or a guardian. Resolves to true when sent. */
export default class KemMessageModal extends LightningModal {
  @api learnerAccountId;
  @api recipients = [];
  @api emailLive = false;
  channelOptions = CHANNELS;
  recipientId;
  channel = "Both";
  subject = "";
  body = "";
  errorMessage;
  isBusy = false;

  connectedCallback() {
    const payer = this.recipients.find((r) => r.feePayer);
    this.recipientId = (payer || this.recipients[0])?.contactId;
  }

  get recipientOptions() {
    return this.recipients.map((r) => ({
      label: `${r.name} (${r.role})`,
      value: r.contactId
    }));
  }
  get selected() {
    return this.recipients.find((r) => r.contactId === this.recipientId);
  }
  get emailWarning() {
    if (this.channel === "Portal" || !this.selected) {
      return null;
    }
    if (!this.selected.email) {
      return `${this.selected.name} has no email address: the email will be recorded as suppressed.`;
    }
    if (this.selected.optedOut) {
      return `${this.selected.name} has opted out of email: the email will be recorded as suppressed.`;
    }
    if (!this.emailLive) {
      return "Email delivery is switched off: the email will be logged but not sent.";
    }
    return null;
  }
  get cannotSend() {
    return (
      this.isBusy ||
      !this.recipientId ||
      !this.subject.trim() ||
      !this.body.trim()
    );
  }

  handleRecipient(event) {
    this.recipientId = event.detail.value;
  }
  handleChannel(event) {
    this.channel = event.detail.value;
  }
  handleSubject(event) {
    this.subject = event.target.value || "";
  }
  handleBody(event) {
    this.body = event.target.value || "";
  }
  handleCancel() {
    this.close(false);
  }

  async handleSend() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await sendMessage({
        request: {
          learnerAccountId: this.learnerAccountId,
          recipientId: this.recipientId,
          channel: this.channel,
          subject: this.subject.trim(),
          body: this.body.trim()
        }
      });
      this.close(true);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
