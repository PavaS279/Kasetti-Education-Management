import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getAdmission from "@salesforce/apex/CollegeAdmissionController.getAdmission";
import captureConsent from "@salesforce/apex/CollegeAdmissionController.captureConsent";
import verifyDocument from "@salesforce/apex/CollegeAdmissionController.verifyDocument";
import markDocumentsVerified from "@salesforce/apex/CollegeAdmissionController.markDocumentsVerified";
import scheduleInterview from "@salesforce/apex/CollegeAdmissionController.scheduleInterview";
import recordOutcome from "@salesforce/apex/CollegeAdmissionController.recordOutcome";
import admit from "@salesforce/apex/CollegeAdmissionController.admit";
import reject from "@salesforce/apex/CollegeAdmissionController.reject";

const UNDECIDED = [
  "Processing",
  "In Review",
  "Documents Verified",
  "Interview Scheduled",
  "Ready For Decision"
];

/** College admission page: desk consent and document checks, Dean interview, admit or reject. */
export default class KemCollegeAdmission extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  admission;
  errorMessage;
  interviewAt = new Date().toISOString();
  outcome = "Pass";
  remarks = "";
  rejectReason = "";

  outcomeOptions = [
    { label: "Pass", value: "Pass" },
    { label: "Reject", value: "Reject" }
  ];

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.admission = await getAdmission({ applicationId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.admission = undefined;
      this.errorMessage =
        error?.body?.message || "The admission could not be loaded.";
    }
  }

  get verdictClass() {
    const status = this.admission?.eligibility;
    if (status === "Eligible" || status === "Overridden") {
      return "verdict ok";
    }
    return status === "Not Eligible" ? "verdict bad" : "verdict";
  }

  get hasSuggestions() {
    return Boolean(this.admission?.suggestions?.length);
  }

  get rollLabel() {
    return this.admission?.rollNumber || "issued when the fee is received";
  }

  get undecided() {
    return UNDECIDED.includes(this.admission?.stage);
  }

  get items() {
    return (this.admission?.items || []).map((i) => {
      const done = i.status === "Accepted" || i.status === "Waived";
      let statusLabel = i.status;
      if (i.last4) {
        statusLabel += ` · ends ${i.last4}`;
      }
      if (i.fileDeleted) {
        statusLabel += " · file removed";
      }
      return {
        ...i,
        optional: !i.required,
        identity: i.sensitiveClass === "Identity",
        statusLabel,
        canVerify:
          this.admission.canDesk &&
          this.admission.consent &&
          !done &&
          this.undecided
      };
    });
  }

  get canMarkVerified() {
    const stage = this.admission?.stage;
    return (
      this.admission?.canDesk &&
      this.admission?.consent &&
      (stage === "Processing" || stage === "In Review")
    );
  }

  get showSchedule() {
    return this.admission?.stage === "Documents Verified";
  }

  get showOutcome() {
    return this.admission?.stage === "Interview Scheduled";
  }

  get showDecision() {
    return this.undecided;
  }

  get canAdmit() {
    return (
      this.admission?.stage === "Ready For Decision" &&
      this.admission?.outcome === "Pass"
    );
  }

  handleInterviewAt(event) {
    this.interviewAt = event.target.value;
  }

  handleOutcome(event) {
    this.outcome = event.detail.value;
  }

  handleRemarks(event) {
    this.remarks = event.target.value;
  }

  handleRejectReason(event) {
    this.rejectReason = event.target.value;
  }

  handleConsent() {
    return this.run(
      () => captureConsent({ applicationId: this.recordId }),
      "Privacy consent recorded"
    );
  }

  handleVerify(event) {
    const itemId = event.target.dataset.id;
    const input = this.template.querySelector(
      `lightning-input[data-id="${itemId}"]`
    );
    return this.run(
      () =>
        verifyDocument({
          applicationId: this.recordId,
          itemId,
          last4: input ? input.value : null
        }),
      "Document verified"
    );
  }

  handleMarkVerified() {
    return this.run(
      () => markDocumentsVerified({ applicationId: this.recordId }),
      "Documents verified — ready for the Dean"
    );
  }

  handleSchedule() {
    return this.run(
      () =>
        scheduleInterview({
          applicationId: this.recordId,
          interviewAt: this.interviewAt
        }),
      "Interview scheduled"
    );
  }

  handleRecordOutcome() {
    return this.run(
      () =>
        recordOutcome({
          applicationId: this.recordId,
          outcome: this.outcome,
          remarks: this.remarks
        }),
      "Interview outcome recorded"
    );
  }

  handleAdmit() {
    return this.run(
      () => admit({ applicationId: this.recordId }),
      "Admitted — seat reserved and annual invoice issued"
    );
  }

  handleReject() {
    return this.run(
      () => reject({ applicationId: this.recordId, reason: this.rejectReason }),
      "Admission rejected"
    );
  }

  openItem(event) {
    event.preventDefault();
    this.navigate(event.target.dataset.id);
  }

  openEnrolment() {
    this.navigate(this.admission.programmeEnrolmentId);
  }

  navigate(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, actionName: "view" }
    });
  }

  async run(action, success) {
    try {
      this.admission = await action();
      this.dispatchEvent(
        new ShowToastEvent({ title: success, variant: "success" })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Not saved",
          message: error?.body?.message,
          variant: "error"
        })
      );
    }
  }
}
