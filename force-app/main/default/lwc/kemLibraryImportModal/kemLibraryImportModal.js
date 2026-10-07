import { api } from "lwc";
import LightningModal from "lightning/modal";
import previewImport from "@salesforce/apex/LibrarySetupController.previewImport";
import importItems from "@salesforce/apex/LibrarySetupController.importItems";
import { reduceErrors } from "c/kemUtils";

const TEMPLATE =
  "Title,Code,Type,Author,Subject,Copies,Location,Loan days,Daily fine,Replacement cost\n" +
  '"Wings of Fire",KT-BK-101,Book,"Kalam, A P J Abdul",Biography,3,Shelf A,14,5,350\n' +
  "Arduino Starter Kit,KT-KIT-101,Kit,,Robotics,2,Lab cupboard,7,20,2500\n";
const MAX_BYTES = 1024 * 1024;

/**
 * Library catalogue import for a branch: choose or paste a CSV, preview what
 * happens to each line (new item, copies added, or why it is skipped), then
 * import. Resolves to the import result, or null.
 */
export default class KemLibraryImportModal extends LightningModal {
  @api branchId;
  @api branchName;
  csv = "";
  fileName;
  preview;
  errorMessage;
  isBusy = false;

  get heading() {
    return this.branchName
      ? `Import library items · ${this.branchName}`
      : "Import library items";
  }

  get templateHref() {
    return `data:text/csv;charset=utf-8,${encodeURIComponent(TEMPLATE)}`;
  }

  get rows() {
    return (this.preview?.rows || []).map((r) => ({
      ...r,
      key: `line-${r.line}`,
      actionClass:
        r.action === "Error"
          ? "kem-badge kem-badge_danger"
          : r.action === "New"
            ? "kem-badge kem-badge_success"
            : "kem-badge"
    }));
  }

  get summary() {
    const p = this.preview;
    if (!p) {
      return "";
    }
    const parts = [
      `${p.newItems} new`,
      `${p.addCopies} with copies added`,
      `${p.copies} copies in all`
    ];
    if (p.errors) {
      parts.push(`${p.errors} skipped`);
    }
    return parts.join(" · ");
  }

  get cannotPreview() {
    return this.isBusy || !this.csv.trim();
  }

  get cannotImport() {
    return (
      this.isBusy ||
      !this.preview ||
      this.preview.newItems + this.preview.addCopies === 0
    );
  }

  get importLabel() {
    const n = this.preview ? this.preview.newItems + this.preview.addCopies : 0;
    return `Import ${n} line${n === 1 ? "" : "s"}`;
  }

  handleFile(event) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    if (file.size > MAX_BYTES) {
      this.errorMessage = "Choose a file under 1 MB (about 5,000 lines).";
      return;
    }
    this.fileName = file.name;
    const reader = new FileReader();
    reader.onload = () => {
      this.csv = String(reader.result || "");
      this.preview = undefined;
      this.runPreview();
    };
    reader.readAsText(file);
  }

  handlePaste(event) {
    this.csv = event.target.value || "";
    this.fileName = undefined;
    this.preview = undefined;
  }

  handlePreview() {
    this.runPreview();
  }

  async runPreview() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.preview = await previewImport({
        branchId: this.branchId,
        csv: this.csv
      });
    } catch (error) {
      this.preview = undefined;
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleCancel() {
    this.close(null);
  }

  async handleImport() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await importItems({
        branchId: this.branchId,
        csv: this.csv
      });
      this.close(result);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
