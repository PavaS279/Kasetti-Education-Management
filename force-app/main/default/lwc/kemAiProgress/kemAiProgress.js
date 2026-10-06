import { LightningElement, api, wire } from "lwc";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import learnerProgress from "@salesforce/apex/AiController.learnerProgress";
import review from "@salesforce/apex/AiController.review";
import getTimeline from "@salesforce/apex/MessageController.getTimeline";
import sendMessage from "@salesforce/apex/MessageController.sendMessage";
import { reduceErrors, toast } from "c/kemUtils";

/** Einstein progress summary for the family: reviewed, edited and sent by staff. */
export default class KemAiProgress extends LightningElement {
  @api recordId;
  available = false;
  result;
  recipients = [];
  recipientId;
  errorMessage;
  isBusy = false;

  @wire(isAvailable, { feature: "Progress Summary" })
  wiredAvailable({ data }) {
    this.available = data === true;
  }

  get recipientOptions() {
    return this.recipients.map((r) => ({
      label: `${r.name} (${r.role}${r.feePayer ? ", fee payer" : ""})`,
      value: r.contactId
    }));
  }

  async handleDraft() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const [result, timeline] = await Promise.all([
        learnerProgress({ learnerAccountId: this.recordId }),
        this.recipients.length
          ? Promise.resolve(null)
          : getTimeline({ learnerAccountId: this.recordId })
      ]);
      this.result = result;
      if (timeline) {
        this.recipients = timeline.recipients || [];
        const payer =
          this.recipients.find((r) => r.feePayer) || this.recipients[0];
        this.recipientId = payer?.contactId;
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleRecipient(event) {
    this.recipientId = event.detail.value;
  }

  async handleUse(event) {
    const { text, interactionId, rating } = event.detail;
    if (!this.recipientId) {
      this.errorMessage = "Choose who receives the summary.";
      return;
    }
    this.isBusy = true;
    try {
      await sendMessage({
        request: {
          learnerAccountId: this.recordId,
          recipientId: this.recipientId,
          channel: "Both",
          subject: "Progress update",
          body: text
        }
      });
      await review({
        interactionId,
        outcome: "Edited",
        finalText: text,
        rating: rating || null,
        feedback: null
      });
      toast(
        this,
        "Progress update sent",
        "The family receives it in the portal (and by email when delivery is on)."
      );
      this.result = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleDiscard() {
    this.result = undefined;
  }
}
