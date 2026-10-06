import { LightningElement, api, wire } from "lwc";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import classLearners from "@salesforce/apex/AiController.classLearners";
import reportComment from "@salesforce/apex/AiController.reportComment";
import useReportComment from "@salesforce/apex/AiController.useReportComment";
import { reduceErrors, toast } from "c/kemUtils";

/** Report-card comment drafts per learner: draft with Einstein, edit, save. */
export default class KemAiReportComments extends LightningElement {
  @api recordId;
  available = false;
  learners = [];
  activeId;
  result;
  errorMessage;
  isBusy = false;

  @wire(isAvailable, { feature: "Report Comment" })
  wiredAvailable({ data }) {
    this.available = data === true;
    if (this.available) {
      this.load();
    }
  }

  async load() {
    try {
      this.learners = await classLearners({ offeringId: this.recordId });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get rows() {
    return this.learners.map((l) => ({
      ...l,
      active: l.enrolmentId === this.activeId,
      hasComment: !!l.comment
    }));
  }
  get hasRows() {
    return this.learners.length > 0;
  }

  async handleDraft(event) {
    this.activeId = event.currentTarget.dataset.id;
    await this.draft();
  }

  async draft() {
    this.isBusy = true;
    this.errorMessage = undefined;
    this.result = undefined;
    try {
      this.result = await reportComment({ enrolmentId: this.activeId });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async handleUse(event) {
    const { text, interactionId } = event.detail;
    this.isBusy = true;
    try {
      await useReportComment({
        enrolmentId: this.activeId,
        comment: text,
        interactionId
      });
      toast(this, "Comment saved", "It appears on the report card.");
      this.activeId = undefined;
      this.result = undefined;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleDiscard() {
    this.activeId = undefined;
    this.result = undefined;
  }
}
