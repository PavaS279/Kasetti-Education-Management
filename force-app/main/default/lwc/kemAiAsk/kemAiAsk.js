import { LightningElement, wire } from "lwc";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import askPolicy from "@salesforce/apex/AiController.askPolicy";
import review from "@salesforce/apex/AiController.review";
import { reduceErrors } from "c/kemUtils";

const EXAMPLES = [
  "Who can approve a refund I requested?",
  "How long is a waitlist seat held?",
  "What is the late fee for library books?"
];

/** Staff policy assistant: answers only from the institution's policies, with sources. */
export default class KemAiAsk extends LightningElement {
  available = false;
  question = "";
  answer;
  asked;
  errorMessage;
  isBusy = false;
  reviewed = false;
  examples = EXAMPLES.map((text, i) => ({ key: String(i), text }));

  @wire(isAvailable, { feature: "Policy Q&A" })
  wiredAvailable({ data }) {
    this.available = data === true;
  }

  get cannotAsk() {
    return this.isBusy || this.question.trim().length < 5;
  }
  get hasSources() {
    return this.answer?.sources?.length > 0;
  }
  get confidenceLabel() {
    return this.answer?.confident
      ? "From the policies"
      : "Not found in the policies — check with an administrator";
  }
  get confidenceClass() {
    return `kem-badge ${this.answer?.confident ? "kem-badge_success" : "kem-badge_warning"}`;
  }

  handleQuestion(event) {
    this.question = event.target.value || "";
  }
  handleKey(event) {
    if (event.key === "Enter" && !this.cannotAsk) {
      this.handleAsk();
    }
  }
  handleExample(event) {
    this.question = event.currentTarget.dataset.text;
    this.handleAsk();
  }

  async handleAsk() {
    this.isBusy = true;
    this.errorMessage = undefined;
    this.reviewed = false;
    try {
      this.asked = this.question.trim();
      this.answer = await askPolicy({ question: this.asked });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async handleFeedback(event) {
    const helpful = event.currentTarget.dataset.helpful === "true";
    try {
      if (this.answer?.interactionId) {
        await review({
          interactionId: this.answer.interactionId,
          outcome: helpful ? "Accepted" : "Rejected",
          finalText: null,
          rating: helpful ? 5 : 2,
          feedback: helpful ? null : this.asked
        });
      }
    } catch {
      // Feedback is optional.
    }
    this.reviewed = true;
  }
}
