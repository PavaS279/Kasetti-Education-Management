import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getDocuments from "@salesforce/apex/DocumentController.getDocuments";
import generateDocument from "@salesforce/apex/DocumentController.generateDocument";
import { reduceErrors, toastError, relativeTime } from "c/kemUtils";

const LABELS = {
  Student_Invoice__c: "Invoice PDF",
  Student_Payment__c: "Receipt PDF",
  IndividualApplication: "Offer letter"
};

/** Generated documents of a record, with one click to create or open the PDF. */
export default class KemDocuments extends NavigationMixin(LightningElement) {
  @api recordId;
  @api objectApiName;
  documents;
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.documents = await getDocuments({ recordId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get documentLabel() {
    return LABELS[this.objectApiName] || "Document";
  }
  get items() {
    return (this.documents || []).map((d) => ({
      ...d,
      meta: `${d.kind} · ${relativeTime(d.createdDate)} · ${d.createdBy}`
    }));
  }
  get hasDocuments() {
    return this.documents && this.documents.length > 0;
  }
  get actionLabel() {
    return this.hasDocuments
      ? `Open ${this.documentLabel.toLowerCase()}`
      : `Create ${this.documentLabel.toLowerCase()}`;
  }

  preview(documentId) {
    this[NavigationMixin.Navigate]({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: documentId }
    });
  }

  handleOpen(event) {
    this.preview(event.currentTarget.dataset.id);
  }

  async handleGenerate() {
    this.isBusy = true;
    try {
      const documentId = await generateDocument({ recordId: this.recordId });
      await this.load();
      this.preview(documentId);
    } catch (error) {
      toastError(this, error, "The document could not be created");
    } finally {
      this.isBusy = false;
    }
  }
}
