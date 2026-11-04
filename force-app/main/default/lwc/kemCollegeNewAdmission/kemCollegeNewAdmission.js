import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import AdmissionWizard from "c/kemCollegeAdmissionWizard";

/** Admission desk launcher: opens the guided college admission and then the new admission. */
export default class KemCollegeNewAdmission extends NavigationMixin(
  LightningElement
) {
  async handleOpen() {
    const admissionId = await AdmissionWizard.open({
      size: "large",
      description: "New college admission"
    });
    if (!admissionId) {
      return;
    }
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Admission created",
        message: "Next: verify the documents on the admission.",
        variant: "success"
      })
    );
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: admissionId, actionName: "view" }
    });
  }
}
