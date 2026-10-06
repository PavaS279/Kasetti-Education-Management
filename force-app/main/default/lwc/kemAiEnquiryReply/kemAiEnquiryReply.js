import { LightningElement, api, wire } from "lwc";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import draftEnquiryReply from "@salesforce/apex/AiController.draftEnquiryReply";
import recordEnquiryReply from "@salesforce/apex/AiController.recordEnquiryReply";
import { reduceErrors, toast } from "c/kemUtils";

/** Einstein reply draft for an enquiry; the counsellor edits, sends it from their mailbox and records it. */
export default class KemAiEnquiryReply extends LightningElement {
  @api recordId;
  available = false;
  note = "";
  result;
  errorMessage;
  isBusy = false;

  @wire(isAvailable, { feature: "Enquiry Reply" })
  wiredAvailable({ data }) {
    this.available = data === true;
  }

  handleNote(event) {
    this.note = event.target.value || "";
  }

  async handleDraft() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.result = await draftEnquiryReply({
        leadId: this.recordId,
        note: this.note
      });
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
      if (navigator.clipboard) {
        await navigator.clipboard.writeText(text);
      }
      await recordEnquiryReply({
        leadId: this.recordId,
        reply: text,
        interactionId
      });
      toast(
        this,
        "Reply recorded",
        "Copied to the clipboard and logged on the enquiry. Send it from your mailbox."
      );
      this.result = undefined;
      this.note = "";
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
