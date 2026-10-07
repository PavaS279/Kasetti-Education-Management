import LightningModal from "lightning/modal";
import getOverview from "@salesforce/apex/DiscountSetupController.getOverview";
import { reduceErrors } from "c/kemUtils";

/** New discount. Resolves to the new Id, or null. */
export default class KemDiscountModal extends LightningModal {
  branches = [];
  courses = [];
  errorMessage;
  isLoading = true;

  get heading() {
    return "New discount";
  }

  async connectedCallback() {
    try {
      const o = await getOverview();
      this.branches = o.branches || [];
      this.courses = o.courses || [];
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  handleSaved(event) {
    this.close(event.detail.id);
  }

  handleCancel() {
    this.close(null);
  }
}
