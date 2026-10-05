import { api } from "lwc";
import LightningModal from "lightning/modal";
import getTemplatePreview from "@salesforce/apex/BranchController.getTemplatePreview";
import cloneBranch from "@salesforce/apex/BranchController.cloneBranch";
import { reduceErrors } from "c/kemUtils";

const PARTS = [
  { key: "includeRooms", label: "Rooms", count: "rooms" },
  { key: "includePrices", label: "Branch prices", count: "prices" },
  { key: "includeDiscounts", label: "Branch discounts", count: "discounts" },
  { key: "includeClosures", label: "Upcoming closures", count: "closures" },
  {
    key: "includeClasses",
    label: "Classes and weekly patterns",
    count: "classes"
  }
];

/**
 * Opens a new branch from an existing branch used as a template.
 * Resolves to the new branch Id, or null when cancelled.
 */
export default class KemBranchCloneModal extends LightningModal {
  @api branchId;
  preview;
  result;
  errorMessage;
  isBusy = false;
  form = {
    name: "",
    code: "",
    invoicePrefix: "",
    city: "",
    email: "",
    phone: "",
    classStartDate: null,
    includeRooms: true,
    includePrices: true,
    includeDiscounts: true,
    includeClosures: true,
    includeClasses: true
  };

  async connectedCallback() {
    try {
      this.preview = await getTemplatePreview({ branchId: this.branchId });
      this.form = { ...this.form, classStartDate: this.preview.suggestedStart };
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get label() {
    return this.preview
      ? `New branch from ${this.preview.name}`
      : "New branch from template";
  }
  get isLoading() {
    return !this.preview && !this.errorMessage;
  }
  get showForm() {
    return this.preview && !this.result;
  }
  get notAllowed() {
    return this.preview && !this.preview.canCreate;
  }
  get parts() {
    return PARTS.map((p) => {
      let count = `${this.preview[p.count]}`;
      if (p.key === "includeClasses") {
        count += ` · ${this.preview.patterns} patterns`;
      }
      return { ...p, count, checked: this.form[p.key] };
    });
  }
  get showStartDate() {
    return this.form.includeClasses && this.preview.classes > 0;
  }
  get cannotSubmit() {
    const f = this.form;
    return (
      this.isBusy ||
      !this.preview?.canCreate ||
      !f.name.trim() ||
      !f.code.trim() ||
      !f.invoicePrefix.trim() ||
      (this.showStartDate && !f.classStartDate)
    );
  }
  get summary() {
    const r = this.result;
    return [
      { key: "rooms", label: "Rooms", value: r.rooms },
      { key: "prices", label: "Prices", value: r.prices },
      { key: "discounts", label: "Discounts", value: r.discounts },
      { key: "closures", label: "Closures", value: r.closures },
      { key: "classes", label: "Classes", value: r.classes },
      { key: "patterns", label: "Weekly patterns", value: r.patterns }
    ];
  }
  get notes() {
    return (this.result.notes || []).map((text, i) => ({
      key: String(i),
      text
    }));
  }
  get hasNotes() {
    return this.notes.length > 0;
  }

  handleField(event) {
    const field = event.target.dataset.field;
    let value = event.target.value || "";
    if (field === "code" || field === "invoicePrefix") {
      value = value.toUpperCase();
    }
    this.form = { ...this.form, [field]: value };
  }
  handleToggle(event) {
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.target.checked
    };
  }
  handleCancel() {
    this.close(null);
  }
  handleDone() {
    this.close(this.result.branchId);
  }

  async handleSubmit() {
    this.isBusy = true;
    this.errorMessage = undefined;
    const f = this.form;
    try {
      this.result = await cloneBranch({
        request: {
          sourceBranchId: this.branchId,
          name: f.name.trim(),
          code: f.code.trim(),
          invoicePrefix: f.invoicePrefix.trim(),
          city: f.city.trim(),
          email: f.email.trim(),
          phone: f.phone.trim(),
          includeRooms: f.includeRooms,
          includePrices: f.includePrices,
          includeDiscounts: f.includeDiscounts,
          includeClosures: f.includeClosures,
          includeClasses: f.includeClasses,
          classStartDate: f.classStartDate || null
        }
      });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
