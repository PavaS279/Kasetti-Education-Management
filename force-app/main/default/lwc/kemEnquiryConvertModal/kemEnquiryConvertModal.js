import { api } from "lwc";
import LightningModal from "lightning/modal";
import getConversionPreview from "@salesforce/apex/EnquiryController.getConversionPreview";
import convertEnquiry from "@salesforce/apex/EnquiryController.convertEnquiry";
import { reduceErrors, initials, toneFor } from "c/kemUtils";

export default class KemEnquiryConvertModal extends LightningModal {
  @api label;
  @api recordId;
  preview;
  errorMessage;
  isLoading = true;
  isSaving = false;
  learnerChoice = "new";
  guardianChoice = "new";
  createApplication = true;

  async connectedCallback() {
    try {
      this.preview = await getConversionPreview({ leadId: this.recordId });
      if (this.preview.learnerMatch) {
        this.learnerChoice = "existing";
      }
      if (this.preview.guardianMatch) {
        this.guardianChoice = "existing";
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get learnerName() {
    const e = this.preview.enquiry;
    return [e.FirstName, e.LastName].filter(Boolean).join(" ");
  }

  get guardianName() {
    const e = this.preview.enquiry;
    return [e.Guardian_First_Name__c, e.Guardian_Last_Name__c]
      .filter(Boolean)
      .join(" ");
  }

  get learnerInitials() {
    return initials(this.learnerName);
  }

  get guardianInitials() {
    return initials(this.guardianName);
  }

  get learnerAvatarClass() {
    return `kem-avatar ${toneFor(this.learnerName)}`;
  }

  get guardianAvatarClass() {
    return `kem-avatar ${toneFor(this.guardianName)}`;
  }

  get learnerOptions() {
    return [
      {
        label: `Use existing: ${this.preview.learnerMatch.Name}`,
        value: "existing"
      },
      { label: "Create a new learner", value: "new" }
    ];
  }

  get guardianOptions() {
    const options = [];
    if (this.preview.guardianMatch) {
      options.push({
        label: `Use existing: ${this.preview.guardianMatch.Name}`,
        value: "existing"
      });
    }
    options.push({ label: "Create a new guardian", value: "new" });
    options.push({ label: "Do not link a guardian", value: "skip" });
    return options;
  }

  get courseLabel() {
    const e = this.preview.enquiry;
    return (
      e.Interested_Course__r?.Name ||
      e.Interested_Program__r?.Name ||
      "not selected"
    );
  }

  get branchLabel() {
    return this.preview.enquiry.Branch__r?.Name || "not selected";
  }

  get isConvertDisabled() {
    return this.isLoading || this.isSaving || !this.preview;
  }

  handleLearnerChoice(event) {
    this.learnerChoice = event.detail.value;
  }

  handleGuardianChoice(event) {
    this.guardianChoice = event.detail.value;
  }

  handleApplicationToggle(event) {
    this.createApplication = event.target.checked;
  }

  handleCancel() {
    this.close(null);
  }

  async handleConvert() {
    this.isSaving = true;
    this.disableClose = true;
    this.errorMessage = undefined;
    const request = {
      leadId: this.recordId,
      existingLearnerId:
        this.learnerChoice === "existing" ? this.preview.learnerMatch.Id : null,
      existingGuardianId:
        this.guardianChoice === "existing"
          ? this.preview.guardianMatch?.Id
          : null,
      createGuardian: this.guardianChoice !== "skip",
      createApplication: this.createApplication
    };
    try {
      const result = await convertEnquiry({ request });
      this.disableClose = false;
      this.close(result);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
      this.disableClose = false;
    } finally {
      this.isSaving = false;
    }
  }
}
