import { LightningElement, api } from "lwc";
import review from "@salesforce/apex/AiController.review";

/**
 * Review panel for an Einstein draft. Fires:
 *  - use: { text, interactionId, edited } when the reviewer uses the (edited) draft
 *  - regenerate
 *  - discard (after recording the rejection)
 */
export default class KemAiDraft extends LightningElement {
  @api useLabel = "Use";
  @api editable = false;
  @api busy = false;
  rating;
  _result;
  text = "";

  @api
  get result() {
    return this._result;
  }
  set result(value) {
    this._result = value;
    this.text = value?.text || "";
    this.rating = undefined;
  }

  get hasResult() {
    return !!this._result;
  }
  get footer() {
    const r = this._result;
    if (!r) {
      return "";
    }
    const model = (r.model || "").replace("sfdc_ai__Default", "");
    return `Einstein · ${model}${r.latencyMs ? ` · ${(r.latencyMs / 1000).toFixed(1)} s` : ""} · review before use`;
  }
  get stars() {
    return [1, 2, 3, 4, 5].map((n) => ({
      value: n,
      label: `Rate ${n} of 5`,
      className: `star${this.rating >= n ? " star_on" : ""}`
    }));
  }
  get readOnly() {
    return !this.editable;
  }
  get edited() {
    return this.text.trim() !== (this._result?.text || "").trim();
  }

  handleText(event) {
    this.text = event.target.value || "";
  }

  handleRate(event) {
    this.rating = Number(event.currentTarget.dataset.value);
    // The rating is stored with the outcome when the draft is used or discarded.
  }

  handleUse() {
    this.dispatchEvent(
      new CustomEvent("use", {
        detail: {
          text: this.text,
          interactionId: this._result?.interactionId,
          edited: this.edited,
          rating: this.rating
        }
      })
    );
  }

  handleRegenerate() {
    this.dispatchEvent(new CustomEvent("regenerate"));
  }

  async handleDiscard() {
    try {
      if (this._result?.interactionId) {
        await review({
          interactionId: this._result.interactionId,
          outcome: "Rejected",
          finalText: null,
          rating: this.rating || null,
          feedback: null
        });
      }
    } catch {
      // Recording the outcome must not block the reviewer.
    }
    this.dispatchEvent(new CustomEvent("discard"));
  }
}
