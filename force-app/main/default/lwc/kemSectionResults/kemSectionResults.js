import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSectionPanel from "@salesforce/apex/CollegeAcademicController.getSectionPanel";
import finaliseResults from "@salesforce/apex/CollegeAcademicController.finaliseResults";
import reopenResults from "@salesforce/apex/CollegeAcademicController.reopenResults";

/** Section page: subject results per section subject, Dean finalise and reopen. */
export default class KemSectionResults extends LightningElement {
  @api recordId;
  subjects = [];
  canFinalise = false;
  canReopen = false;
  loaded = false;
  errorMessage;
  reopenId;
  reason = "";

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      const panel = await getSectionPanel({ sectionId: this.recordId });
      this.canFinalise = panel.canFinalise;
      this.canReopen = panel.canReopen;
      this.subjects = (panel.subjects || []).map((s) => ({
        ...s,
        isFinal: s.status === "Results Final",
        results: (s.results || []).map((r) => ({
          ...r,
          isFinal: r.status === "Final"
        }))
      }));
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Subject results could not be loaded.";
    }
    this.loaded = true;
  }

  get isEmpty() {
    return this.loaded && !this.errorMessage && this.subjects.length === 0;
  }

  get showReason() {
    return Boolean(this.reopenId);
  }

  async handleFinalise(event) {
    const id = event.target.dataset.id;
    await this.run(
      () => finaliseResults({ sectionSubjectId: id }),
      "Results finalised and published"
    );
  }

  handleReopen(event) {
    this.reopenId = event.target.dataset.id;
    this.reason = "";
  }

  handleReason(event) {
    this.reason = event.target.value;
  }

  cancelReopen() {
    this.reopenId = undefined;
  }

  async confirmReopen() {
    const ids = [this.reopenId];
    const reason = this.reason;
    this.reopenId = undefined;
    await this.run(
      () => reopenResults({ subjectResultIds: ids, reason }),
      "Result reopened"
    );
  }

  async run(action, success) {
    try {
      await action();
      this.dispatchEvent(
        new ShowToastEvent({ title: success, variant: "success" })
      );
      await this.load();
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
