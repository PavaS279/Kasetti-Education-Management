import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import getEnrollableClasses from "@salesforce/apex/EnrolmentController.getEnrollableClasses";
import previewTransfer from "@salesforce/apex/TransferController.previewTransfer";
import transfer from "@salesforce/apex/TransferController.transfer";
import { reduceErrors } from "c/kemUtils";

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "";
}

/** Moves an enrolment to another class. Resolves to the new enrolment Id, or null. */
export default class KemTransferModal extends LightningModal {
  @api enrolmentId;
  @api learnerName;
  @api currentOfferingId;
  @api branchId;
  currencyCode = CURRENCY;
  classes = [];
  targetId;
  effectiveDate = new Date().toISOString().slice(0, 10);
  reason = "";
  preview;
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.loadClasses();
  }

  get heading() {
    return `Transfer ${this.learnerName}`;
  }
  get classOptions() {
    return this.classes
      .filter((c) => c.Id !== this.currentOfferingId)
      .map((c) => {
        const free = c.Seats_Available__c;
        return {
          ...c,
          course: c.LearningCourse?.Name,
          meta: [c.Branch__r?.Name, c.Delivery_Mode__c, formatDate(c.StartDate)]
            .filter(Boolean)
            .join(" · "),
          seats: c.EnrollmentCapacity ? `${free} free` : "Unlimited",
          selected: c.Id === this.targetId ? "true" : "false",
          className: `option${c.Id === this.targetId ? " option_selected" : ""}`
        };
      });
  }
  get noClasses() {
    return this.classOptions.length === 0;
  }
  get differenceClass() {
    const d = this.preview?.difference || 0;
    return d > 0 ? "diff diff_up" : d < 0 ? "diff diff_down" : "diff";
  }
  get hasBlockers() {
    return this.preview?.blockers?.length > 0;
  }
  get cannotTransfer() {
    return (
      this.isBusy || !this.preview || this.hasBlockers || !this.reason.trim()
    );
  }

  async loadClasses() {
    try {
      this.classes = await getEnrollableClasses({
        courseId: null,
        branchId: this.branchId || null
      });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  async loadPreview() {
    if (!this.targetId) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.preview = await previewTransfer({ request: this.request() });
    } catch (error) {
      this.preview = undefined;
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  request() {
    return {
      enrolmentId: this.enrolmentId,
      targetOfferingId: this.targetId,
      effectiveDate: this.effectiveDate,
      reason: this.reason
    };
  }

  handlePick(event) {
    this.targetId = event.currentTarget.dataset.id;
    this.loadPreview();
  }
  handleDate(event) {
    this.effectiveDate = event.target.value;
    this.loadPreview();
  }
  handleReason(event) {
    this.reason = event.target.value || "";
  }
  handleCancel() {
    this.close(null);
  }

  async handleTransfer() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const newId = await transfer({ request: this.request() });
      this.close(newId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
