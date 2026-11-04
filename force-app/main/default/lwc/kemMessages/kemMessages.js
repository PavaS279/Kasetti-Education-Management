import { LightningElement, api } from "lwc";
import getTimeline from "@salesforce/apex/MessageController.getTimeline";
import setEmailOptOut from "@salesforce/apex/MessageController.setEmailOptOut";
import MessageModal from "c/kemMessageModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const FILTERS = [
  { value: "all", label: "All" },
  { value: "Email", label: "Email" },
  { value: "Portal", label: "Portal" },
  { value: "attention", label: "Not delivered" }
];
const ATTENTION = ["Suppressed", "Not Sent", "Failed"];
const STATUS_CLASS = {
  Queued: "kem-badge kem-badge_info",
  Sent: "kem-badge kem-badge_success",
  Delivered: "kem-badge kem-badge_success",
  Suppressed: "kem-badge kem-badge_warning",
  "Not Sent": "kem-badge",
  Failed: "kem-badge kem-badge_danger"
};
const EVENT_ICON = {
  Invoice_Issued: "utility:file",
  Payment_Received: "utility:moneybag",
  Invoice_Due_Soon: "utility:clock",
  Invoice_Overdue: "utility:warning",
  Waitlist_Offer: "utility:event",
  Refund_Paid: "utility:undo",
  Session_Cancelled: "utility:ban",
  "Staff Message": "utility:chat"
};

function formatWhen(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short"
      }).format(new Date(value))
    : "";
}

/** Learner message timeline: notifications and staff messages, with email consent. */
export default class KemMessages extends LightningElement {
  @api recordId;
  timeline;
  errorMessage;
  filter = "all";
  expandedId;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.timeline = await getTimeline({ learnerAccountId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get filters() {
    return FILTERS.map((f) => ({
      ...f,
      className: `pill${f.value === this.filter ? " pill_on" : ""}`,
      pressed: f.value === this.filter ? "true" : "false"
    }));
  }
  get people() {
    return this.timeline.recipients.map((r) => ({
      ...r,
      chipClass: `person${r.optedOut ? " person_out" : ""}`,
      consentLabel: !r.email
        ? "No email"
        : r.optedOut
          ? "Opted out of email"
          : "Email allowed",
      toggleLabel: r.optedOut ? "Allow email" : "Opt out",
      canToggle: this.timeline.canManageConsent && !!r.email
    }));
  }
  get messages() {
    return this.timeline.messages
      .filter((m) => {
        if (this.filter === "all") {
          return true;
        }
        if (this.filter === "attention") {
          return ATTENTION.includes(m.Status__c);
        }
        return m.Channel__c === this.filter;
      })
      .map((m) => ({
        ...m,
        icon: EVENT_ICON[m.Event__c] || "utility:email",
        statusClass: STATUS_CLASS[m.Status__c] || "kem-badge",
        channelIcon:
          m.Channel__c === "Email" ? "utility:email" : "utility:home",
        recipient: m.Recipient__r?.Name,
        sender: m.Sent_By__r?.Name,
        when: formatWhen(m.Sent_On__c || m.CreatedDate),
        expanded: m.Id === this.expandedId,
        expandedLabel: m.Id === this.expandedId ? "true" : "false"
      }));
  }
  get isEmpty() {
    return this.messages.length === 0;
  }
  get deliveryOff() {
    return !this.timeline.emailLive;
  }

  handleFilter(event) {
    this.filter = event.currentTarget.dataset.value;
  }

  handleToggle(event) {
    const id = event.currentTarget.dataset.id;
    this.expandedId = this.expandedId === id ? undefined : id;
  }

  async handleNew() {
    const sent = await MessageModal.open({
      size: "medium",
      learnerAccountId: this.recordId,
      recipients: this.timeline.recipients,
      emailLive: this.timeline.emailLive
    });
    if (sent) {
      toast(this, "Message sent", "It appears in the timeline below.");
      await this.load();
    }
  }

  async handleConsent(event) {
    const contactId = event.currentTarget.dataset.id;
    const person = this.timeline.recipients.find(
      (r) => r.contactId === contactId
    );
    this.isBusy = true;
    try {
      await setEmailOptOut({
        learnerAccountId: this.recordId,
        contactId,
        optedOut: !person.optedOut
      });
      toast(
        this,
        "Consent updated",
        person.optedOut
          ? `${person.name} will receive emails again.`
          : `${person.name} will no longer receive emails.`
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not update consent");
    } finally {
      this.isBusy = false;
    }
  }
}
