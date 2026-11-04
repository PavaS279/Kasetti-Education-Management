import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import {
  MessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import CLASS_CHANGED from "@salesforce/messageChannel/KEM_Class_Changed__c";
import getWaitlist from "@salesforce/apex/WaitlistController.getWaitlist";
import acceptOffer from "@salesforce/apex/WaitlistController.acceptOffer";
import declineOffer from "@salesforce/apex/WaitlistController.declineOffer";
import removeFromWaitlist from "@salesforce/apex/WaitlistController.removeFromWaitlist";
import requeue from "@salesforce/apex/WaitlistController.requeue";
import JoinModal from "c/kemWaitlistJoinModal";
import ReasonModal from "c/kemReasonModal";
import {
  reduceErrors,
  toast,
  toastError,
  initials,
  toneFor,
  relativeTime
} from "c/kemUtils";

const STATUS_CLASS = {
  Waiting: "kem-badge kem-badge_info",
  Offered: "kem-badge kem-badge_warning",
  Enrolled: "kem-badge kem-badge_success",
  Declined: "kem-badge",
  Expired: "kem-badge kem-badge_danger",
  Cancelled: "kem-badge"
};
const PRIORITY_LABEL = { 1: "Priority", 2: "Urgent" };

function timeLeft(value) {
  const ms = new Date(value).getTime() - Date.now();
  if (ms <= 0) {
    return "Offer expired";
  }
  const hours = Math.floor(ms / 3600000);
  return hours >= 24
    ? `Reply within ${Math.floor(hours / 24)}d ${hours % 24}h`
    : `Reply within ${hours}h ${Math.floor((ms % 3600000) / 60000)}m`;
}

/** Class waitlist: queue order, seat holds with countdowns, and the answers families give. */
export default class KemWaitlist extends NavigationMixin(LightningElement) {
  @api recordId;
  view;
  errorMessage;
  isBusy = false;
  showClosed = false;

  @wire(MessageContext) messageContext;

  connectedCallback() {
    this.load();
    this.subscription = subscribe(
      this.messageContext,
      CLASS_CHANGED,
      (message) => {
        if (message.offeringId === this.recordId && !this.isBusy) {
          this.load();
        }
      }
    );
  }

  disconnectedCallback() {
    unsubscribe(this.subscription);
  }

  async load() {
    try {
      this.view = await getWaitlist({ offeringId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get seats() {
    const v = this.view;
    return [
      { key: "cap", label: "Capacity", value: v.capacity ?? "∞" },
      { key: "taken", label: "Taken", value: v.taken },
      { key: "held", label: "Held for offers", value: v.reserved },
      { key: "free", label: "Free", value: v.available ?? "∞" },
      { key: "waiting", label: "Waiting", value: this.waitingCount }
    ];
  }
  get waitingCount() {
    return this.view.entries.filter((e) => e.status === "Waiting").length;
  }
  get active() {
    return this.rows.filter((r) => r.isActive);
  }
  get closed() {
    return this.rows.filter((r) => !r.isActive);
  }
  get noActive() {
    return this.active.length === 0;
  }
  get className() {
    return this.view?.className || "this class";
  }
  get hasClosed() {
    return this.closed.length > 0;
  }
  get closedToggleLabel() {
    return this.showClosed
      ? "Hide history"
      : `Show history (${this.closed.length})`;
  }
  get rows() {
    return this.view.entries.map((e) => {
      const offered = e.status === "Offered";
      return {
        ...e,
        isActive: e.status === "Waiting" || offered,
        initials: initials(e.learnerName),
        avatarClass: `kem-avatar ${toneFor(e.learnerName)}`,
        statusClass: STATUS_CLASS[e.status] || "kem-badge",
        priorityLabel: PRIORITY_LABEL[e.priority],
        positionLabel: e.position ? `#${e.position}` : "",
        meta: offered
          ? timeLeft(e.offerExpires)
          : `Requested ${relativeTime(e.requestedOn)}`,
        metaClass: offered ? "meta meta_urgent" : "meta",
        canAccept: offered && this.view.canManage,
        canRemove: (e.status === "Waiting" || offered) && this.view.canManage,
        canRequeue:
          (e.status === "Expired" || e.status === "Declined") &&
          this.view.canManage,
        isEnrolled: e.status === "Enrolled" && e.enrolmentId
      };
    });
  }

  handleToggleClosed() {
    this.showClosed = !this.showClosed;
  }

  changed() {
    publish(this.messageContext, CLASS_CHANGED, { offeringId: this.recordId });
  }

  async run(action, title, message) {
    this.isBusy = true;
    try {
      await action();
      toast(this, title, message);
      await this.load();
      this.changed();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  async handleJoin() {
    const entryId = await JoinModal.open({
      size: "small",
      offeringId: this.recordId,
      className: this.className
    });
    if (entryId) {
      toast(
        this,
        "Added to the waitlist",
        "The learner will be offered the next free seat."
      );
      await this.load();
      this.changed();
    }
  }

  handleAccept(event) {
    const entryId = event.currentTarget.dataset.id;
    this.run(
      () => acceptOffer({ entryId }),
      "Learner enrolled",
      "The held seat was taken at today's price."
    );
  }

  async askReason(label, confirmLabel, required) {
    return ReasonModal.open({
      size: "small",
      label,
      message: required
        ? "The seat passes to the next learner in the queue."
        : "Optional: why did the family say no?",
      confirmLabel,
      confirmVariant: "destructive"
    });
  }

  async handleDecline(event) {
    const entryId = event.currentTarget.dataset.id;
    const reason = await this.askReason(
      "Family declined the seat",
      "Record decline",
      false
    );
    if (reason) {
      this.run(
        () => declineOffer({ entryId, reason }),
        "Decline recorded",
        "The seat was offered to the next learner."
      );
    }
  }

  async handleRemove(event) {
    const entryId = event.currentTarget.dataset.id;
    const reason = await this.askReason("Remove from waitlist", "Remove", true);
    if (reason) {
      this.run(
        () => removeFromWaitlist({ entryId, reason }),
        "Removed from the waitlist",
        "Any held seat passed to the next learner."
      );
    }
  }

  handleRequeue(event) {
    const entryId = event.currentTarget.dataset.id;
    this.run(
      () => requeue({ entryId }),
      "Back in the queue",
      "The learner keeps their original place."
    );
  }

  handleNavigate(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
