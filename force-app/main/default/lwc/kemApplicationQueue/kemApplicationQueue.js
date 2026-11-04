import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import getQueue from "@salesforce/apex/ApplicationController.getQueue";
import getBranches from "@salesforce/apex/EnquiryController.getBranches";
import { reduceErrors, initials, toneFor, relativeTime } from "c/kemUtils";

const LABELS = {
  Processing: "Processing",
  "In Review": "In review",
  "Ready For Decision": "Ready for decision",
  Offered: "Offer out"
};
const ELIGIBILITY = {
  Eligible: "kem-badge kem-badge_success",
  "Not Eligible": "kem-badge kem-badge_danger",
  Overridden: "kem-badge kem-badge_info"
};

export default class KemApplicationQueue extends NavigationMixin(
  LightningElement
) {
  branchId = "";
  branchOptions = [{ label: "All branches", value: "" }];
  raw = [];
  errorMessage;
  wiredResult;

  @wire(getBranches)
  wiredBranches({ data }) {
    if (data) {
      this.branchOptions = [
        { label: "All branches", value: "" },
        ...data.map((b) => ({ label: b.Name, value: b.Id }))
      ];
    }
  }

  @wire(getQueue, { branchId: "$branchParam" })
  wiredQueue(result) {
    this.wiredResult = result;
    if (result.data) {
      this.raw = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get branchParam() {
    return this.branchId || null;
  }

  get columns() {
    return this.raw.map((column) => {
      const cards = column.applications.map((a) => {
        const applicant = a.Account?.Name || "Applicant";
        return {
          ...a,
          applicant,
          initials: initials(applicant),
          avatarClass: `kem-avatar ${toneFor(applicant)}`,
          course: a.Learning_Course__r?.Name || "Course not selected",
          checklistLabel: a.Checklist_Complete__c
            ? "Checklist complete"
            : "Checklist open",
          checklistClass: a.Checklist_Complete__c
            ? "kem-badge kem-badge_success"
            : "kem-badge kem-badge_warning",
          eligibilityClass: ELIGIBILITY[a.Eligibility_Status__c] || "kem-badge",
          offerLabel:
            a.Offer_Status__c === "Offered" && a.Offer_Expiry_Date__c
              ? `Expires ${relativeTime(a.Offer_Expiry_Date__c)}`
              : null,
          waiting: a.AppliedDate ? `Applied ${relativeTime(a.AppliedDate)}` : ""
        };
      });
      return {
        stage: column.stage,
        label: LABELS[column.stage] || column.stage,
        cards,
        count: cards.length,
        isEmpty: cards.length === 0
      };
    });
  }

  handleBranch(event) {
    this.branchId = event.detail.value;
  }

  handleRefresh() {
    refreshApex(this.wiredResult);
  }

  handleOpen(event) {
    this.navigate(event.currentTarget.dataset.id);
  }

  handleKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.navigate(event.currentTarget.dataset.id);
    }
  }

  navigate(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "IndividualApplication",
        actionName: "view"
      }
    });
  }
}
