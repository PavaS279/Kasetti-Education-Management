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
  /** College enquiries: declared marks the desk confirms or corrects. */
  qualifications = [];
  entrances = [];
  marksConfirmed = false;

  async connectedCallback() {
    try {
      this.preview = await getConversionPreview({ leadId: this.recordId });
      if (this.preview.learnerMatch) {
        this.learnerChoice = "existing";
      }
      if (this.preview.guardianMatch) {
        this.guardianChoice = "existing";
      }
      if (this.preview.college) {
        this.qualifications = (this.preview.college.qualifications || []).map(
          (q, index) => ({ ...q, key: `q${index}` })
        );
        this.entrances = (this.preview.college.entrances || []).map(
          (e, index) => ({ ...e, key: `e${index}` })
        );
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

  get isCollege() {
    return Boolean(this.preview?.college);
  }

  get collegeRouteLabel() {
    return this.preview.college.entryRoute === "Lateral"
      ? "Year 2 (lateral entry)"
      : "Year 1 (regular)";
  }

  get qualificationRows() {
    return this.qualifications.map((q) => ({
      ...q,
      label: [q.level, q.stream || q.branchCode].filter(Boolean).join(" ")
    }));
  }

  get hasEntrances() {
    return this.entrances.length > 0;
  }

  get collegeBlocked() {
    return this.isCollege && !this.preview.college.canConvert;
  }

  get isConvertDisabled() {
    return (
      this.isLoading ||
      this.isSaving ||
      !this.preview ||
      this.collegeBlocked ||
      (this.isCollege && !this.marksConfirmed)
    );
  }

  handleQualification(event) {
    const key = event.target.dataset.key;
    const value = event.target.value === "" ? null : Number(event.target.value);
    this.qualifications = this.qualifications.map((q) => {
      if (q.key !== key) {
        return q;
      }
      return { ...q, percentage: value };
    });
  }

  handleEntrance(event) {
    const key = event.target.dataset.key;
    const value = event.target.value === "" ? null : Number(event.target.value);
    this.entrances = this.entrances.map((e) => {
      if (e.key !== key) {
        return e;
      }
      return { ...e, rank: value };
    });
  }

  handleMarksConfirmed(event) {
    this.marksConfirmed = event.target.checked;
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
    if (this.isCollege) {
      // eslint-disable-next-line no-unused-vars
      request.qualifications = this.qualifications.map(({ key, ...q }) => q);
      // eslint-disable-next-line no-unused-vars
      request.entrances = this.entrances.map(({ key, ...e }) => e);
      request.marksConfirmed = this.marksConfirmed;
    }
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
