import { LightningElement, api, wire } from "lwc";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import applicationDocuments from "@salesforce/apex/AiController.applicationDocuments";
import documentContent from "@salesforce/apex/AiController.documentContent";
import extractDocument from "@salesforce/apex/AiController.extractDocument";
import applyExtraction from "@salesforce/apex/AiController.applyExtraction";
import review from "@salesforce/apex/AiController.review";
import { readPdfText } from "c/kemPdfText";
import { reduceErrors, toast } from "c/kemUtils";

const FEATURE = "Document Extraction";
const MAX_UPLOAD_BYTES = 4 * 1024 * 1024;
const SOURCES = [
  { label: "Attached", value: "attached" },
  { label: "From computer", value: "upload" },
  { label: "Paste text", value: "paste" }
];

function sectionOrder(section) {
  return ["Learner", "Address", "Guardian", "Education"].indexOf(section);
}

/**
 * AI document reader on the application page: reads an admission document
 * (PDF text or pasted text) and proposes learner, guardian and school
 * details next to what is on record. Staff tick, correct and apply.
 */
export default class KemAiDocumentReader extends LightningElement {
  @api recordId;
  available = false;
  source = "attached";
  documents;
  pasted = "";
  stage = "choose";
  busyLabel;
  errorMessage;
  extraction;
  proposals = [];
  documentName;
  applied;

  sources = SOURCES;

  @wire(isAvailable, { feature: FEATURE })
  wiredAvailable({ data }) {
    this.available = data === true;
    if (this.available && this.documents === undefined) {
      this.loadDocuments();
    }
  }

  async loadDocuments() {
    try {
      this.documents = await applicationDocuments({
        applicationId: this.recordId
      });
    } catch (error) {
      this.documents = [];
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get isBusy() {
    return Boolean(this.busyLabel);
  }
  get isChoose() {
    return this.stage === "choose";
  }
  get isReview() {
    return this.stage === "review";
  }
  get isDone() {
    return this.stage === "done";
  }
  get isAttached() {
    return this.source === "attached";
  }
  get isUpload() {
    return this.source === "upload";
  }
  get isPaste() {
    return this.source === "paste";
  }
  get hasDocuments() {
    return (this.documents || []).length > 0;
  }
  get documentRows() {
    return (this.documents || []).map((d) => ({
      ...d,
      meta: `${d.fileType || "File"} · ${d.sizeKb} KB · ${d.attachedTo}`,
      disabled: !d.readable || this.isBusy
    }));
  }
  get pasteDisabled() {
    return this.isBusy || this.pasted.trim().length < 20;
  }
  get sections() {
    const groups = new Map();
    this.proposals.forEach((p) => {
      if (!groups.has(p.section)) {
        groups.set(p.section, []);
      }
      groups.get(p.section).push({
        ...p,
        rowClass: `row${p.differs ? " row_differs" : ""}`,
        currentLabel: p.current || "—",
        disabled: !p.selectable
      });
    });
    return [...groups.entries()]
      .sort((a, b) => sectionOrder(a[0]) - sectionOrder(b[0]))
      .map(([name, rows]) => ({ name, rows }));
  }
  get selectedCount() {
    return this.proposals.filter((p) => p.selected && p.selectable).length;
  }
  get applyDisabled() {
    return this.isBusy || this.selectedCount === 0;
  }
  get applyLabel() {
    return `Apply ${this.selectedCount} selected`;
  }
  get summary() {
    if (!this.extraction) {
      return "";
    }
    const type = this.extraction.documentType
      ? `${this.extraction.documentType} · `
      : "";
    return `${type}${this.extraction.found} details found in ${this.documentName}`;
  }
  get guardianHint() {
    return this.extraction && !this.extraction.hasGuardian
      ? "No guardian is linked yet: ticking the guardian's last name adds them as fee payer and emergency contact."
      : "";
  }
  get appliedSummary() {
    if (!this.applied) {
      return "";
    }
    const parts = [];
    if (this.applied.learnerFields) {
      parts.push(`${this.applied.learnerFields} learner details updated`);
    }
    if (this.applied.guardianAdded) {
      parts.push("guardian added");
    }
    if (this.applied.guardianFields) {
      parts.push(`${this.applied.guardianFields} guardian details updated`);
    }
    if (this.applied.detailsNoted) {
      parts.push("school details noted on the application");
    }
    return parts.join(", ");
  }

  handleSource(event) {
    this.source = event.detail.value;
    this.errorMessage = undefined;
  }

  handlePaste(event) {
    this.pasted = event.target.value || "";
  }

  async handleReadAttached(event) {
    const id = event.currentTarget.dataset.id;
    const doc = (this.documents || []).find((d) => d.contentVersionId === id);
    await this.run("Reading the document", async () => {
      const content = await documentContent({ contentVersionId: id });
      const text =
        content.kind === "pdf"
          ? (await readPdfText(this, content.base64)).text
          : content.text;
      await this.extract(doc ? doc.title : content.title, text);
    });
  }

  async handleUpload(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }
    if (file.size > MAX_UPLOAD_BYTES) {
      this.errorMessage = "Choose a file smaller than 4 MB.";
      return;
    }
    await this.run("Reading the document", async () => {
      let text;
      if (/\.pdf$/i.test(file.name) || file.type === "application/pdf") {
        text = (await readPdfText(this, await file.arrayBuffer())).text;
      } else if (/\.(txt|csv)$/i.test(file.name) || /^text\//.test(file.type)) {
        text = await file.text();
      } else {
        throw new Error(
          "Only PDF and text files can be read. Scanned images need OCR, which is not available."
        );
      }
      await this.extract(file.name, text);
    });
  }

  async handleReadPasted() {
    await this.run("Reading the text", () =>
      this.extract("Pasted text", this.pasted)
    );
  }

  async extract(name, text) {
    if (!text || text.trim().length < 20) {
      throw new Error(
        "This document has no readable text (it may be a scan or photo). Type the details instead, or paste the text."
      );
    }
    this.busyLabel = "Einstein is reading the details";
    this.documentName = name;
    this.extraction = await extractDocument({
      applicationId: this.recordId,
      documentName: name,
      text
    });
    this.proposals = this.extraction.proposals.map((p) => ({ ...p }));
    this.stage = "review";
  }

  async run(label, action) {
    this.busyLabel = label;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.busyLabel = undefined;
    }
  }

  handleToggle(event) {
    const key = event.target.dataset.key;
    const selected = event.target.checked;
    this.proposals = this.proposals.map(function update(p) {
      return p.key === key ? { ...p, selected } : p;
    });
  }

  handleValue(event) {
    const key = event.target.dataset.key;
    const proposed = event.target.value;
    this.proposals = this.proposals.map(function update(p) {
      return p.key === key ? { ...p, proposed } : p;
    });
  }

  async handleApply() {
    const changes = this.proposals
      .filter((p) => p.selected && p.selectable)
      .map((p) => ({ key: p.key, value: p.proposed }));
    await this.run("Saving", async () => {
      this.applied = await applyExtraction({
        applicationId: this.recordId,
        interactionId: this.extraction.interactionId,
        documentName: this.documentName,
        changes
      });
      this.stage = "done";
      toast(this, "Details applied", this.appliedSummary, "success");
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    });
  }

  async handleDiscard() {
    if (this.extraction?.interactionId) {
      try {
        await review({
          interactionId: this.extraction.interactionId,
          outcome: "Rejected",
          finalText: null,
          rating: null,
          feedback: null
        });
      } catch {
        // The review is optional.
      }
    }
    this.reset();
  }

  reset() {
    this.stage = "choose";
    this.extraction = undefined;
    this.proposals = [];
    this.applied = undefined;
    this.errorMessage = undefined;
  }
}
