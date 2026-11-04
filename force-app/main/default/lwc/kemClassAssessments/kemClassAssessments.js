import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import getClassAssessments from "@salesforce/apex/AssessmentController.getClassAssessments";
import { reduceErrors } from "c/kemUtils";

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "No date";
}

export default class KemClassAssessments extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  assessments;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.assessments = await getClassAssessments({
        offeringId: this.recordId
      });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get items() {
    return (this.assessments || []).map((a) => {
      const published = a.Status__c === "Published";
      const avg = a.Average_Percentage__c;
      return {
        ...a,
        meta: `${a.Assessment_Type__c || "Assessment"} · ${formatDate(a.Assessment_Date__c)} · out of ${a.Max_Score__c}`,
        statusClass: published
          ? "kem-badge kem-badge_success"
          : "kem-badge kem-badge_warning",
        avgLabel:
          published && avg !== null && avg !== undefined
            ? `${Math.round(avg)}% avg`
            : null
      };
    });
  }

  get isEmpty() {
    return this.assessments && this.assessments.length === 0;
  }

  get countLabel() {
    return this.assessments
      ? `Assessments (${this.assessments.length})`
      : "Assessments";
  }

  handleOpen(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Course_Assessment__c",
        actionName: "new"
      },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({
          Course_Offering__c: this.recordId,
          Grade_Scale__c: "Standard"
        }),
        useRecordTypeCheck: 1
      }
    });
  }

  handleRefresh() {
    this.load();
  }
}
