import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import {
  MessageContext,
  publish,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import CLASS_CHANGED from "@salesforce/messageChannel/KEM_Class_Changed__c";
import CURRENCY from "@salesforce/i18n/currency";
import getRoster from "@salesforce/apex/EnrolmentController.getRoster";
import withdraw from "@salesforce/apex/EnrolmentController.withdraw";
import decideDiscount from "@salesforce/apex/EnrolmentController.decideDiscount";
import EnrolModal from "c/kemEnrolModal";
import PatternModal from "c/kemPatternModal";
import generateSessions from "@salesforce/apex/TimetableController.generateSessions";
import createInvoice from "@salesforce/apex/BillingController.createInvoice";
import ReasonModal from "c/kemReasonModal";
import TransferModal from "c/kemTransferModal";
import { reduceErrors, toast, toastError, initials, toneFor } from "c/kemUtils";

const ACTIVE = ["Enrolled", "On Hold"];
const STATUS_CLASS = {
  Enrolled: "kem-badge kem-badge_success",
  "On Hold": "kem-badge kem-badge_warning",
  Completed: "kem-badge kem-badge_info",
  Withdrew: "kem-badge kem-badge_danger"
};
const APPROVAL_CLASS = {
  Pending: "kem-badge kem-badge_warning",
  Approved: "kem-badge kem-badge_success",
  Rejected: "kem-badge kem-badge_danger"
};

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "—";
}

export default class KemClassRoster extends NavigationMixin(LightningElement) {
  @api recordId;
  currencyCode = CURRENCY;
  roster;
  errorMessage;
  wiredResult;

  @wire(MessageContext) messageContext;

  connectedCallback() {
    // The waitlist on the same page enrols learners; refresh when it does.
    this.subscription = subscribe(
      this.messageContext,
      CLASS_CHANGED,
      (message) => {
        if (message.offeringId === this.recordId && this.wiredResult) {
          refreshApex(this.wiredResult);
        }
      }
    );
  }

  disconnectedCallback() {
    unsubscribe(this.subscription);
  }

  /** Tells the waitlist that seats may have changed. */
  announceChange() {
    publish(this.messageContext, CLASS_CHANGED, { offeringId: this.recordId });
  }

  @wire(getRoster, { offeringId: "$recordId" })
  wiredRoster(result) {
    this.wiredResult = result;
    if (result.data) {
      this.roster = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get offering() {
    return this.roster.offering;
  }
  get courseName() {
    return this.offering.LearningCourse?.Name || "Class";
  }
  get branchName() {
    return this.offering.Branch__r?.Name || "No branch";
  }
  get teacherName() {
    return (
      this.offering.Teacher_User__r?.Name ||
      this.offering.PrimaryFaculty?.Name ||
      "Teacher not assigned"
    );
  }
  get roomName() {
    return this.offering.Room__r?.Name || "Room not assigned";
  }
  get statusLabel() {
    return this.offering.Class_Status__c || "Planned";
  }
  get isClosed() {
    return !["Open", "In Progress"].includes(this.offering.Class_Status__c);
  }
  get capacityLabel() {
    return this.offering.EnrollmentCapacity ?? "∞";
  }
  get meterStyle() {
    const capacity = this.offering.EnrollmentCapacity;
    const pct = capacity
      ? Math.min(100, Math.round((100 * this.roster.seatsTaken) / capacity))
      : 0;
    return `width: ${pct}%`;
  }
  get meterLabel() {
    return `${this.roster.seatsTaken} of ${this.capacityLabel} seats taken`;
  }
  get seatsLeftLabel() {
    const capacity = this.offering.EnrollmentCapacity;
    if (!capacity) {
      return "No seat limit";
    }
    const left = capacity - this.roster.seatsTaken;
    return left > 0
      ? `${left} seat${left === 1 ? "" : "s"} left`
      : "Class is full";
  }
  get periodLabel() {
    return `${formatDate(this.offering.StartDate)} – ${formatDate(this.offering.EndDate)}`;
  }
  get rows() {
    return this.roster.rows.map((r) => ({
      ...r,
      initials: initials(r.learnerName),
      avatarClass: `kem-avatar kem-avatar_sm ${toneFor(r.learnerName)}`,
      statusClass: STATUS_CLASS[r.status] || "kem-badge",
      approvalClass: APPROVAL_CLASS[r.discountApproval] || "kem-badge",
      startLabel: formatDate(r.startDate),
      isActive: ACTIVE.includes(r.status),
      canDecide:
        this.roster.canApproveDiscounts && r.discountApproval === "Pending",
      canInvoice:
        this.roster.canManageBilling &&
        r.billingStatus === "Not Invoiced" &&
        r.status !== "Withdrew" &&
        r.discountApproval !== "Pending"
    }));
  }
  get isEmpty() {
    return this.roster.rows.length === 0;
  }

  handleNavigate(event) {
    event.preventDefault();
    this.navigate(event.currentTarget.dataset.id);
  }

  navigate(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, actionName: "view" }
    });
  }

  async handleEnrol() {
    const result = await EnrolModal.open({
      size: "medium",
      label: `Enrol into ${this.offering.Name}`,
      offeringId: this.recordId,
      courseId: this.offering.LearningCourseId,
      branchId: this.offering.Branch__c
    });
    if (result?.enrolmentId) {
      toast(
        this,
        "Learner enrolled",
        result.approvalRequired
          ? "Enrolled; the discount awaits finance approval."
          : "The enrolment and agreed price were saved."
      );
      await refreshApex(this.wiredResult);
      this.announceChange();
    }
  }

  async handleScheduleAction(event) {
    const action = event.detail.value;

    if (action === "timetable") {
      this[NavigationMixin.Navigate]({
        type: "standard__navItemPage",
        attributes: { apiName: "KEM_Timetable" }
      });

      return;
    }

    if (action === "pattern") {
      const id = await PatternModal.open({
        size: "medium",
        label: "Add weekly pattern",
        offeringId: this.recordId,
        offeringName: this.offering.Name
      });

      if (id) {
        toast(
          this,
          "Pattern saved",
          "Generate sessions to fill the timetable."
        );
      }

      return;
    }

    try {
      const result = await generateSessions({ offeringId: this.recordId });

      const extra = result.conflicts.length
        ? ` ${result.conflicts.length} could not be scheduled: ${result.conflicts.join("; ")}`
        : "";

      toast(
        this,

        "Sessions generated",

        `${result.created} created, ${result.skippedExisting} already existed, ${result.skippedClosures} skipped for closures.${extra}`,

        result.conflicts.length ? "warning" : "success"
      );
    } catch (error) {
      toastError(this, error, "Sessions could not be generated");
    }
  }

  async handleRowAction(event) {
    const enrolmentId = event.currentTarget.dataset.id;
    const action = event.detail.value;
    try {
      if (action === "open") {
        this.navigate(enrolmentId);
        return;
      }
      if (action === "invoice") {
        const invoiceId = await createInvoice({ enrolmentId, issueNow: true });
        toast(
          this,
          "Invoice issued",
          "The invoice was raised to the fee payer."
        );
        this.navigate(invoiceId);
        await refreshApex(this.wiredResult);
        this.announceChange();
        this.announceChange();
        return;
      }
      if (action === "transfer") {
        const row = this.roster.rows.find((r) => r.enrolmentId === enrolmentId);
        const newId = await TransferModal.open({
          size: "medium",
          enrolmentId,
          learnerName: row?.learnerName,
          currentOfferingId: this.recordId,
          branchId: this.offering.Branch__c
        });
        if (newId) {
          toast(
            this,
            "Learner transferred",
            "The seat here was released and the history kept."
          );
          await refreshApex(this.wiredResult);
          this.announceChange();
        }
        return;
      }
      if (action === "withdraw") {
        const reason = await ReasonModal.open({
          size: "small",
          label: "Withdraw learner",
          message:
            "The seat is released today and the enrolment is kept for history.",
          confirmLabel: "Withdraw",
          confirmVariant: "destructive"
        });
        if (!reason) {
          return;
        }
        await withdraw({ enrolmentId, reason, effectiveDate: null });
        toast(this, "Learner withdrawn", "The seat was released.");
      } else {
        await decideDiscount({ enrolmentId, approve: action === "approve" });
        toast(
          this,
          "Discount decided",
          action === "approve"
            ? "Discount approved."
            : "Discount rejected; the enrolment was re-priced."
        );
      }
      await refreshApex(this.wiredResult);
      this.announceChange();
    } catch (error) {
      toastError(this, error, "Action failed");
    }
  }
}
