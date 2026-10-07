import { LightningElement, api } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import saveDiscount from "@salesforce/apex/DiscountSetupController.saveDiscount";
import { reduceErrors } from "c/kemUtils";

const TYPES = [
  { label: "Percentage", value: "Percentage" },
  { label: "Fixed amount", value: "Fixed Amount" }
];
const FEES = [
  { label: "Any fee", value: "" },
  ...[
    "Tuition",
    "Admission",
    "Materials",
    "Assessment",
    "Transport",
    "Other"
  ].map((v) => ({
    label: v === "Materials" ? "Kit and materials" : v,
    value: v
  }))
];

/**
 * The discount form (new or edit). Fires "saved" with the Id, or "cancel".
 * branches and courses are option lists; discount is a row from the overview.
 */
export default class KemDiscountForm extends LightningElement {
  @api branches = [];
  @api courses = [];
  currencyCode = CURRENCY;
  typeOptions = TYPES;
  feeOptions = FEES;
  form = {
    id: null,
    code: "",
    description: "",
    discountType: "Percentage",
    value: undefined,
    feeType: "Tuition",
    branchId: "",
    courseId: "",
    validFrom: undefined,
    validTo: undefined,
    maxUses: undefined,
    requiresApproval: false,
    active: true
  };
  errorMessage;
  isBusy = false;

  @api
  get discount() {
    return this._discount;
  }
  set discount(value) {
    this._discount = value;
    if (value) {
      this.form = {
        id: value.id,
        code: value.code || "",
        description: value.description || "",
        discountType: value.discountType,
        value: value.value,
        feeType: value.feeType || "",
        branchId: value.branchId || "",
        courseId: value.courseId || "",
        validFrom: value.validFrom,
        validTo: value.validTo,
        maxUses: value.maxUses,
        requiresApproval: Boolean(value.requiresApproval),
        active: value.active !== false
      };
    }
  }

  get branchOptions() {
    return [{ label: "All branches", value: "" }, ...(this.branches || [])];
  }
  get courseOptions() {
    return [{ label: "All courses", value: "" }, ...(this.courses || [])];
  }
  get isPercentage() {
    return this.form.discountType === "Percentage";
  }
  get valueLabel() {
    return this.isPercentage ? "Discount (%)" : "Discount amount";
  }
  get valueMax() {
    return this.isPercentage ? 100 : undefined;
  }
  get isEdit() {
    return Boolean(this.form.id);
  }
  get saveLabel() {
    return this.isEdit ? "Save changes" : "Create discount";
  }
  get example() {
    const v = Number(this.form.value);
    if (!v) {
      return "";
    }
    const base = 2500;
    const off = this.isPercentage ? (base * v) / 100 : Math.min(v, base);
    return `On a ₹${base.toLocaleString("en-IN")} fee this gives ₹${off.toLocaleString("en-IN")} off.`;
  }
  get cannotSave() {
    return (
      this.isBusy || !this.form.code.trim() || !(Number(this.form.value) > 0)
    );
  }

  handleField(event) {
    const field = event.target.dataset.field;
    let value;
    if (event.target.type === "checkbox" || event.target.type === "toggle") {
      value = event.target.checked;
    } else if (event.detail?.value !== undefined) {
      value = event.detail.value;
    } else {
      value = event.target.value;
    }
    if (field === "code") {
      value = (value || "").toUpperCase().replace(/\s+/g, "");
    }
    this.form = { ...this.form, [field]: value };
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  async handleSave() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    if (!inputs.reduce((ok, i) => i.reportValidity() && ok, true)) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    const f = this.form;
    const num = (v) => {
      return v === "" || v === null || v === undefined ? null : Number(v);
    };
    try {
      const id = await saveDiscount({
        request: {
          id: f.id,
          code: f.code,
          description: f.description,
          discountType: f.discountType,
          value: num(f.value),
          feeType: f.feeType || null,
          branchId: f.branchId || null,
          courseId: f.courseId || null,
          validFrom: f.validFrom || null,
          validTo: f.validTo || null,
          maxUses: num(f.maxUses),
          requiresApproval: f.requiresApproval,
          active: f.active
        }
      });
      this.dispatchEvent(new CustomEvent("saved", { detail: { id } }));
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
