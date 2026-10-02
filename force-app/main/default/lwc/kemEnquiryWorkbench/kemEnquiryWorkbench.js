import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import logFollowUp from "@salesforce/apex/EnquiryController.logFollowUp";
import updateStatus from "@salesforce/apex/EnquiryController.updateStatus";
import LostReasonModal from "c/kemLostReasonModal";
import ConvertModal from "c/kemEnquiryConvertModal";
import {
  reduceErrors,
  toast,
  toastError,
  initials,
  toneFor,
  formatDateTime,
  followUpClass
} from "c/kemUtils";

import NAME from "@salesforce/schema/Lead.Name";
import STATUS from "@salesforce/schema/Lead.Status";
import IS_CONVERTED from "@salesforce/schema/Lead.IsConverted";
import EMAIL from "@salesforce/schema/Lead.Email";
import MOBILE from "@salesforce/schema/Lead.MobilePhone";
import PHONE from "@salesforce/schema/Lead.Phone";
import BRANCH_NAME from "@salesforce/schema/Lead.Branch__r.Name";
import COURSE_NAME from "@salesforce/schema/Lead.Interested_Course__r.Name";
import PROGRAM_NAME from "@salesforce/schema/Lead.Interested_Program__r.Name";
import CHANNEL from "@salesforce/schema/Lead.Enquiry_Channel__c";
import DELIVERY from "@salesforce/schema/Lead.Preferred_Delivery_Mode__c";
import NEXT_FOLLOW_UP from "@salesforce/schema/Lead.Next_Follow_Up__c";
import LAST_CONTACTED from "@salesforce/schema/Lead.Last_Contacted__c";
import FOLLOW_UP_STATUS from "@salesforce/schema/Lead.Follow_Up_Status__c";
import DUPLICATE from "@salesforce/schema/Lead.Possible_Duplicate__c";
import DUPLICATE_DETAILS from "@salesforce/schema/Lead.Duplicate_Details__c";
import G_FIRST from "@salesforce/schema/Lead.Guardian_First_Name__c";
import G_LAST from "@salesforce/schema/Lead.Guardian_Last_Name__c";
import G_EMAIL from "@salesforce/schema/Lead.Guardian_Email__c";
import G_PHONE from "@salesforce/schema/Lead.Guardian_Phone__c";
import G_REL from "@salesforce/schema/Lead.Guardian_Relationship__c";

const FIELDS = [
  NAME,
  STATUS,
  IS_CONVERTED,
  BRANCH_NAME,
  COURSE_NAME,
  PROGRAM_NAME,
  CHANNEL,
  NEXT_FOLLOW_UP,
  LAST_CONTACTED,
  FOLLOW_UP_STATUS
];
const OPTIONAL_FIELDS = [
  EMAIL,
  MOBILE,
  PHONE,
  DELIVERY,
  DUPLICATE,
  DUPLICATE_DETAILS,
  G_FIRST,
  G_LAST,
  G_EMAIL,
  G_PHONE,
  G_REL
];
const STAGES = ["New", "Contacted", "Nurturing", "Qualified"];
const OUTCOMES = [
  "Interested",
  "Callback requested",
  "Trial booked",
  "Information sent",
  "Not reachable",
  "Not interested"
];
const DASH = "—";

export default class KemEnquiryWorkbench extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  lead;
  errorMessage;
  showFollowUp = false;
  outcome;
  notes = "";
  nextFollowUpValue;
  isSaving = false;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: FIELDS,
    optionalFields: OPTIONAL_FIELDS
  })
  wiredLead({ data, error }) {
    if (data) {
      this.lead = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  value(field) {
    return getFieldValue(this.lead, field);
  }

  get name() {
    return this.value(NAME);
  }
  get avatarInitials() {
    return initials(this.name);
  }
  get avatarClass() {
    return `kem-avatar kem-avatar_lg ${toneFor(this.name)}`;
  }
  get status() {
    return this.value(STATUS);
  }
  get isOpen() {
    return !this.value(IS_CONVERTED) && this.status !== "Unqualified";
  }
  get courseLabel() {
    return (
      this.value(COURSE_NAME) ||
      this.value(PROGRAM_NAME) ||
      "Course not selected"
    );
  }
  get branchLabel() {
    return this.value(BRANCH_NAME) || "No branch";
  }
  get email() {
    return this.value(EMAIL) || DASH;
  }
  get phone() {
    return this.value(MOBILE) || this.value(PHONE) || DASH;
  }
  get channel() {
    return this.value(CHANNEL) || DASH;
  }
  get deliveryMode() {
    return this.value(DELIVERY) || DASH;
  }
  get guardianName() {
    return (
      [this.value(G_FIRST), this.value(G_LAST)].filter(Boolean).join(" ") ||
      DASH
    );
  }
  get guardianRelationship() {
    return this.value(G_REL) || "";
  }
  get guardianContact() {
    return [this.value(G_PHONE), this.value(G_EMAIL)]
      .filter(Boolean)
      .join(" · ");
  }
  get followUpStatus() {
    return this.value(FOLLOW_UP_STATUS) || "Not Scheduled";
  }
  get followUpBadgeClass() {
    return followUpClass(this.followUpStatus);
  }
  get nextFollowUp() {
    return formatDateTime(this.value(NEXT_FOLLOW_UP)) || DASH;
  }
  get lastContacted() {
    return formatDateTime(this.value(LAST_CONTACTED)) || DASH;
  }
  get isDuplicate() {
    return this.value(DUPLICATE) === true;
  }
  get duplicateDetails() {
    return this.value(DUPLICATE_DETAILS);
  }

  get pathSteps() {
    const current = this.value(IS_CONVERTED) ? "Qualified" : this.status;
    const index = STAGES.indexOf(current);
    if (this.status === "Unqualified") {
      return [...STAGES.slice(0, 3), "Unqualified"].map((label, i) => ({
        label,
        className: i === 3 ? "path-step path-step_lost" : "path-step",
        ariaCurrent: i === 3 ? "step" : null
      }));
    }
    return STAGES.map((label, i) => {
      let className = "path-step";
      if (i < index) {
        className += " path-step_done";
      } else if (i === index) {
        className += " path-step_current";
      }
      return { label, className, ariaCurrent: i === index ? "step" : null };
    });
  }

  get outcomeOptions() {
    return OUTCOMES.map((o) => ({ label: o, value: o }));
  }

  get isSaveDisabled() {
    return this.isSaving || !this.outcome;
  }

  toggleFollowUp() {
    this.showFollowUp = !this.showFollowUp;
    if (this.showFollowUp && !this.nextFollowUpValue) {
      const next = new Date();
      next.setDate(next.getDate() + 2);
      next.setHours(10, 0, 0, 0);
      this.nextFollowUpValue = next.toISOString();
    }
  }

  handleOutcome(event) {
    this.outcome = event.detail.value;
  }
  handleNotes(event) {
    this.notes = event.target.value;
  }
  handleNextFollowUp(event) {
    this.nextFollowUpValue = event.target.value;
  }

  async handleSaveFollowUp() {
    this.isSaving = true;
    try {
      await logFollowUp({
        leadId: this.recordId,
        outcome: this.outcome,
        notes: this.notes,
        nextFollowUp: this.nextFollowUpValue
      });
      toast(
        this,
        "Follow-up logged",
        "The activity was recorded and the next follow-up scheduled."
      );
      this.showFollowUp = false;
      this.outcome = undefined;
      this.notes = "";
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      toastError(this, error, "Follow-up could not be saved");
    } finally {
      this.isSaving = false;
    }
  }

  async handleUnqualified() {
    const reason = await LostReasonModal.open({
      size: "small",
      label: "Mark enquiry as unqualified"
    });
    if (!reason) {
      return;
    }
    try {
      await updateStatus({
        leadId: this.recordId,
        status: "Unqualified",
        lostReason: reason
      });
      toast(this, "Enquiry closed", "The enquiry was marked as unqualified.");
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      toastError(this, error, "Enquiry could not be closed");
    }
  }

  async handleConvert() {
    const result = await ConvertModal.open({
      size: "medium",
      label: "Convert enquiry",
      recordId: this.recordId
    });
    if (result?.learnerId) {
      toast(
        this,
        "Enquiry converted",
        "Learner, guardian, and application are ready."
      );
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: result.learnerId,
          objectApiName: "Account",
          actionName: "view"
        }
      });
    }
  }
}
