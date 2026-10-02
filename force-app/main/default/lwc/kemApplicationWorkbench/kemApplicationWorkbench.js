import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getApplication from "@salesforce/apex/ApplicationController.getApplication";
import performAction from "@salesforce/apex/ApplicationController.performAction";
import decide from "@salesforce/apex/ApplicationController.decide";
import updateChecklistItem from "@salesforce/apex/ApplicationController.updateChecklistItem";
import addChecklistItem from "@salesforce/apex/ApplicationController.addChecklistItem";
import ReasonModal from "c/kemReasonModal";
import DecisionModal from "c/kemDecisionModal";
import EnrolModal from "c/kemEnrolModal";
import { reduceErrors, toast, toastError, formatDateTime } from "c/kemUtils";

const STAGES = [
  "Processing",
  "In Review",
  "Ready For Decision",
  "Application Decision",
  "Enrolled"
];
const STAGE_LABELS = { "Application Decision": "Decision" };
const CLOSED = ["Withdrawn", "Canceled", "Cancelled", "Enrollment Failed"];

const BADGE = {
  Accepted: "kem-badge kem-badge_success",
  Waived: "kem-badge kem-badge_info",
  Rejected: "kem-badge kem-badge_danger",
  Pending: "kem-badge kem-badge_warning",
  Eligible: "kem-badge kem-badge_success",
  Overridden: "kem-badge kem-badge_info",
  "Not Eligible": "kem-badge kem-badge_danger",
  Admit: "kem-badge kem-badge_success",
  Waitlist: "kem-badge kem-badge_warning",
  Reject: "kem-badge kem-badge_danger",
  Offered: "kem-badge kem-badge_info",
  Declined: "kem-badge kem-badge_danger",
  Expired: "kem-badge kem-badge_danger"
};

export default class KemApplicationWorkbench extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  view;
  errorMessage;
  isBusy = false;
  wiredResult;

  @wire(getApplication, { applicationId: "$recordId" })
  wiredApplication(result) {
    this.wiredResult = result;
    if (result.data) {
      this.view = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get app() {
    return this.view?.application;
  }
  get applicantName() {
    return this.app.Account?.Name || "Applicant";
  }
  get courseLabel() {
    return (
      this.app.Learning_Course__r?.Name ||
      this.app.Learning_Program__r?.Name ||
      "Course not selected"
    );
  }
  get branchLabel() {
    return this.app.Branch__r?.Name || "No branch";
  }
  get appliedLabel() {
    return this.app.AppliedDate
      ? `Applied ${formatDateTime(this.app.AppliedDate)}`
      : "Not submitted";
  }
  get reviewerName() {
    return this.app.Reviewer__r?.Name || "unassigned";
  }
  get checklistRequired() {
    return this.view.checklist.filter((i) => i.required).length;
  }
  get checklistDone() {
    return this.checklistRequired - this.view.requiredOpen;
  }
  get ringStyle() {
    const pct =
      this.checklistRequired === 0
        ? 100
        : Math.round((100 * this.checklistDone) / this.checklistRequired);
    return `--progress: ${pct}%`;
  }
  get ringLabel() {
    return `${this.checklistDone} of ${this.checklistRequired} required checklist items complete`;
  }
  get canOverride() {
    return (
      this.view.canOverrideEligibility &&
      this.app.Eligibility_Status__c === "Not Eligible"
    );
  }
  get eligibilityClass() {
    return BADGE[this.app.Eligibility_Status__c] || "kem-badge";
  }
  get decisionClass() {
    return BADGE[this.app.Decision__c] || "kem-badge";
  }
  get offerClass() {
    return BADGE[this.app.Offer_Status__c] || "kem-badge";
  }
  get decisionLine() {
    return [
      this.app.Decided_By__r?.Name,
      formatDateTime(this.app.Decision_Date__c)
    ]
      .filter(Boolean)
      .join(" · ");
  }
  get offerCountdown() {
    if (
      this.app.Offer_Status__c !== "Offered" ||
      !this.app.Offer_Expiry_Date__c
    ) {
      return null;
    }
    const days = Math.ceil(
      (new Date(this.app.Offer_Expiry_Date__c) - new Date()) / 86400000
    );
    return days >= 0
      ? `Expires in ${days} day${days === 1 ? "" : "s"}`
      : "Expired";
  }

  get checklistRows() {
    return this.view.checklist.map((item) => {
      const status = item.status || "New";
      return {
        ...item,
        statusLabel: status,
        statusClass: BADGE[status] || "kem-badge",
        fileLabel: item.fileCount
          ? `${item.fileCount} file${item.fileCount === 1 ? "" : "s"}`
          : "Upload"
      };
    });
  }

  get pathSteps() {
    const status = this.app.Status;
    if (CLOSED.includes(status)) {
      return [
        {
          label: status,
          className: "path-step path-step_lost",
          ariaCurrent: "step"
        }
      ];
    }
    const index = STAGES.indexOf(status);
    return STAGES.map((stage, i) => {
      let className = "path-step";
      if (i < index) {
        className += " path-step_done";
      } else if (i === index) {
        className += " path-step_current";
      }
      return {
        label: STAGE_LABELS[stage] || stage,
        className,
        ariaCurrent: i === index ? "step" : null
      };
    });
  }

  get actions() {
    const status = this.app.Status;
    const list = [];
    if (status === "Processing") {
      list.push({
        name: "submit",
        label: "Submit for review",
        variant: "brand-outline",
        icon: "utility:send"
      });
    } else if (status === "In Review") {
      list.push({
        name: "return",
        label: "Return",
        variant: "inverse",
        icon: "utility:back"
      });
      list.push({
        name: "ready",
        label: "Ready for decision",
        variant: "brand-outline",
        icon: "utility:check"
      });
    } else if (status === "Ready For Decision") {
      list.push({
        name: "decide",
        label: "Decide",
        variant: "brand-outline",
        icon: "utility:approval"
      });
    } else if (
      status === "Application Decision" &&
      this.app.Offer_Status__c === "Offered"
    ) {
      list.push({
        name: "accept",
        label: "Record acceptance",
        variant: "brand-outline",
        icon: "utility:like"
      });
      list.push({
        name: "decline",
        label: "Record decline",
        variant: "inverse",
        icon: "utility:dislike"
      });
    }
    if (
      status === "Application Decision" &&
      this.app.Offer_Status__c === "Accepted"
    ) {
      list.push({
        name: "enrol",
        label: "Enrol in class",
        variant: "brand-outline",
        icon: "utility:adduser"
      });
    }
    if (!CLOSED.includes(status) && status !== "Enrolled") {
      list.push({
        name: "withdraw",
        label: "Withdraw",
        variant: "inverse",
        icon: "utility:close"
      });
    }
    return list;
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

  async refresh() {
    await refreshApex(this.wiredResult);
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
  }

  async run(work, successTitle, successMessage) {
    this.isBusy = true;
    try {
      await work();
      toast(this, successTitle, successMessage);
      await this.refresh();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  async handleAction(event) {
    const name = event.currentTarget.dataset.name;
    if (name === "enrol") {
      const result = await EnrolModal.open({
        size: "medium",
        label: `Enrol ${this.applicantName}`,
        learnerId: this.app.AccountId,
        learnerName: this.applicantName,
        courseId: this.app.Learning_Course__c,
        branchId: this.app.Branch__c,
        offeringId: this.app.Requested_Offering__c,
        applicationId: this.recordId
      });
      if (result?.enrolmentId) {
        toast(
          this,
          "Learner enrolled",
          "The application is now Enrolled and the agreed price was saved."
        );
        await this.refresh();
      }
      return;
    }
    if (name === "decide") {
      const result = await DecisionModal.open({
        size: "small",
        label: "Record admission decision"
      });
      if (result) {
        await this.run(
          () =>
            decide({
              applicationId: this.recordId,
              decision: result.decision,
              reason: result.reason,
              offerValidDays: result.validDays
            }),
          "Decision recorded",
          `${result.decision} recorded for ${this.applicantName}.`
        );
      }
      return;
    }
    let reason = null;
    if (name === "withdraw" || name === "override") {
      reason = await ReasonModal.open({
        size: "small",
        label:
          name === "withdraw" ? "Withdraw application" : "Override eligibility",
        message:
          name === "withdraw"
            ? "The application is closed and kept for reporting."
            : "Overrides are audited with your name and reason.",
        confirmLabel: name === "withdraw" ? "Withdraw" : "Override",
        confirmVariant: name === "withdraw" ? "destructive" : "brand"
      });
      if (!reason) {
        return;
      }
    }
    await this.run(
      () =>
        performAction({ applicationId: this.recordId, action: name, reason }),
      "Application updated",
      "The application was updated."
    );
  }

  async handleItemStatus(event) {
    const itemId = event.currentTarget.dataset.id;
    const status = event.currentTarget.dataset.status;
    let rejectReason = null;
    if (status === "Rejected") {
      rejectReason = await ReasonModal.open({
        size: "small",
        label: "Reject checklist item",
        message: "The applicant will need to resubmit this item.",
        confirmLabel: "Reject",
        confirmVariant: "destructive"
      });
      if (!rejectReason) {
        return;
      }
    }
    await this.run(
      () => updateChecklistItem({ itemId, status, rejectReason }),
      "Checklist updated",
      `Item marked ${status.toLowerCase()}.`
    );
  }

  async handleAddItem() {
    const name = await ReasonModal.open({
      size: "small",
      label: "Add checklist item",
      reasonLabel: "Item name",
      message: "New items are required for this application.",
      confirmLabel: "Add"
    });
    if (name) {
      await this.run(
        () =>
          addChecklistItem({
            applicationId: this.recordId,
            name,
            required: true,
            instruction: null
          }),
        "Item added",
        `${name} was added to the checklist.`
      );
    }
  }

  async handleUploadFinished() {
    toast(
      this,
      "File uploaded",
      "The document was attached to the checklist item."
    );
    await refreshApex(this.wiredResult);
  }
}
