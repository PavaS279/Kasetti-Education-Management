import { api } from "lwc";
import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/FamilySetupController.getChoices";
import createApplication from "@salesforce/apex/FamilySetupController.createApplication";
import { reduceErrors } from "c/kemUtils";

/** New application for an existing learner: course, branch, preferred class. Resolves to the application Id, or null. */
export default class KemApplicationModal extends LightningModal {
  @api learnerId;
  @api learnerName;
  @api branchId;
  selectedBranch;
  courseId;
  offeringId = "";
  branchOptions = [];
  courseOptions = [];
  classes = [];
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return this.learnerName
      ? `New application for ${this.learnerName}`
      : "New application";
  }

  async connectedCallback() {
    this.selectedBranch = this.branchId;
    await this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      const c = await getChoices({ branchId: this.selectedBranch || null });
      this.branchOptions = (c.branches || []).map((b) => ({
        label: b.label,
        value: b.value
      }));
      this.courseOptions = (c.courses || []).map((o) => ({
        label: o.detail ? `${o.label} (${o.detail})` : o.label,
        value: o.value
      }));
      this.classes = c.classes || [];
      if (!this.selectedBranch) {
        this.selectedBranch = c.defaultBranchId;
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get classOptions() {
    return [
      { label: "No preference", value: "" },
      ...this.classes
        .filter((c) => c.detail === this.courseId)
        .map((c) => ({ label: c.label, value: c.value }))
    ];
  }

  get cannotSave() {
    return this.isBusy || !this.courseId || !this.selectedBranch;
  }

  async handleBranch(event) {
    this.selectedBranch = event.detail.value;
    this.offeringId = "";
    await this.load();
  }

  handleCourse(event) {
    this.courseId = event.detail.value;
    this.offeringId = "";
  }

  handleClass(event) {
    this.offeringId = event.detail.value;
  }

  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const id = await createApplication({
        learnerId: this.learnerId,
        branchId: this.selectedBranch,
        courseId: this.courseId,
        offeringId: this.offeringId || null
      });
      this.close(id);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
