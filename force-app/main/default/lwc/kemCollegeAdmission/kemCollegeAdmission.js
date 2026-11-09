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
import givePortal from "@salesforce/apex/CollegeAdmissionController.givePortal";
import sendPortalLink from "@salesforce/apex/CollegeAdmissionController.sendPortalLink";
import setQuota from "@salesforce/apex/CollegeAdmissionController.setQuota";
import requestException from "@salesforce/apex/CollegeAdmissionController.requestException";
import approveException from "@salesforce/apex/CollegeAdmissionController.approveException";
import declineException from "@salesforce/apex/CollegeAdmissionController.declineException";

const UNDECIDED = [
  "Processing",
  "In Review",
  "Documents Verified",
  "Interview Scheduled",
  "Ready For Decision",
  "Awaiting Dean Approval"
];
const DEAN_STAGES = [
  "Awaiting Dean Approval",
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
  exceptionReason = "";
  quotaChoice;
  deanRemarks = "";

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
      this.prefillReason();
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

  /** Section allotment is the Dean's step once the student is enrolled. */
  get showSectionPrompt() {
    return Boolean(this.admission?.needsSection && this.admission?.canDean);
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

  /** Counsellor's decision once the documents are verified. */
  get showDeskDecision() {
    return (
      this.admission?.canDesk && this.admission?.stage === "Documents Verified"
    );
  }
  get admitHint() {
    return this.admission?.exceptionStatus === "Approved"
      ? "The Dean approved the exception. Admitting reserves the seat and issues the invoice."
      : "Meets the criteria. Admitting reserves the seat and issues the invoice.";
  }
  get hasException() {
    return Boolean(this.admission?.exceptionStatus);
  }
  get exceptionClass() {
    const s = this.admission?.exceptionStatus;
    if (s === "Approved") return "exception exception_ok";
    if (s === "Declined") return "exception exception_bad";
    return "exception";
  }
  /** The Dean only sees exception requests (and the old interview flow). */
  get showDean() {
    return (
      this.admission?.canDean && DEAN_STAGES.includes(this.admission?.stage)
    );
  }
  get showSchedule() {
    return this.admission?.stage === "Awaiting Dean Approval";
  }
  get showOutcome() {
    return this.admission?.stage === "Interview Scheduled";
  }
  get showExceptionDecision() {
    return this.admission?.stage === "Awaiting Dean Approval";
  }
  get showLegacyDecision() {
    return (
      this.admission?.stage === "Ready For Decision" &&
      this.admission?.outcome === "Pass"
    );
  }
  get hasQuotas() {
    return Boolean(this.admission?.quotas?.length);
  }
  get quotaLabel() {
    return this.admission?.quotaName || "CET (default)";
  }
  get quotaOptions() {
    return (this.admission?.quotas || []).map((q) => ({
      label: `${q.name} — ${q.available} of ${q.seats} seats left${q.rankExam ? ` · needs a ${q.rankExam} rank` : ""}`,
      value: q.quotaId
    }));
  }
  get quotaValue() {
    return this.quotaChoice || this.admission?.quotaId;
  }
  handleQuotaChoice(event) {
    this.quotaChoice = event.detail.value;
  }
  handleSaveQuota() {
    return this.run(
      () =>
        setQuota({ applicationId: this.recordId, quotaId: this.quotaValue }),
      "Quota saved"
    );
  }
  get showPortal() {
    return Boolean(
      this.admission?.portal && this.admission?.programmeEnrolmentId
    );
  }
  get portalHint() {
    const label = this.admission?.portal?.label;
    if (label === "Needs an email") {
      return "Add the student's email on Student 360, then give access.";
    }
    if (label === "Active") {
      return "The student signs in to see the admission letter, invoice and receipts.";
    }
    if (label === "No free portal licence") {
      return "Free a licence (deactivate a cancelled student's login) and try again.";
    }
    return "";
  }
  handleGivePortal() {
    return this.run(
      () => givePortal({ applicationId: this.recordId }),
      "Portal access requested — the login and the password email follow in a few seconds; refresh to see it"
    );
  }
  async handleSendLink() {
    try {
      const email = await sendPortalLink({ applicationId: this.recordId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: `Password link sent to ${email}`,
          variant: "success"
        })
      );
    } catch (error) {
      this.toastError(error);
    }
  }
  toastError(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Not saved",
        message: error?.body?.message,
        variant: "error"
      })
    );
  }
  /** The reason typed in the new-admission wizard is ready for the request. */
  prefillReason() {
    if (!this.exceptionReason && this.admission?.exceptionReason) {
      this.exceptionReason = this.admission.exceptionReason;
    }
  }

  handleExceptionReason(event) {
    this.exceptionReason = event.target.value;
  }
  handleDeanRemarks(event) {
    this.deanRemarks = event.target.value;
  }
  handleRequestException() {
    return this.run(
      () =>
        requestException({
          applicationId: this.recordId,
          reason: this.exceptionReason
        }),
      "Sent to the Dean for approval"
    );
  }
  handleApproveException() {
    return this.run(
      () =>
        approveException({
          applicationId: this.recordId,
          remarks: this.deanRemarks
        }),
      "Exception approved — the counsellor can admit"
    );
  }
  handleDeclineException() {
    return this.run(
      () =>
        declineException({
          applicationId: this.recordId,
          reason: this.deanRemarks
        }),
      "Exception declined"
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
      "Documents verified"
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
