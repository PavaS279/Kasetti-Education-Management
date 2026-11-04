import { api, LightningElement } from "lwc";
import getRecordHeader from "@salesforce/apex/CollegeCatalogController.getRecordHeader";
import { reduceErrors } from "c/kemUtils";

export default class KemCollegeRecordHeader extends LightningElement {
  @api recordId;
  header;
  errorMessage;

  async connectedCallback() {
    try {
      this.header = await getRecordHeader({ recordId: this.recordId });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }
}
