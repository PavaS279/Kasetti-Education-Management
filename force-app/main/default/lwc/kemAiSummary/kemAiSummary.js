import { LightningElement, api, wire } from "lwc";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import summarise from "@salesforce/apex/AiController.summarise";
import review from "@salesforce/apex/AiController.review";
import { reduceErrors } from "c/kemUtils";

/** Einstein summary of the record with a helpful / not helpful review. */
export default class KemAiSummary extends LightningElement {
  @api recordId;
  available = false;
  result;
  errorMessage;
  isBusy = false;
  reviewed = false;

  @wire(isAvailable, { feature: "Record Summary" })
  wiredAvailable({ data }) {
    this.available = data === true;
  }

  get lines() {
    return (this.result?.text || "")
      .split("\n")
      .map((l) => l.replace(/^\s*[-•*]\s*/, "").trim())
      .filter((l) => l)
      .map((text, i) => ({ key: String(i), text }));
  }
  get footer() {
    return `Einstein · ${(this.result?.model || "").replace("sfdc_ai__Default", "")} · check against the record`;
  }

  async handleSummarise() {
    this.isBusy = true;
    this.errorMessage = undefined;
    this.reviewed = false;
    try {
      this.result = await summarise({ recordId: this.recordId });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async handleFeedback(event) {
    const helpful = event.currentTarget.dataset.helpful === "true";
    try {
      await review({
        interactionId: this.result.interactionId,
        outcome: helpful ? "Accepted" : "Rejected",
        finalText: helpful ? this.result.text : null,
        rating: helpful ? 5 : 2,
        feedback: null
      });
    } catch {
      // Feedback is optional.
    }
    this.reviewed = true;
  }
}
