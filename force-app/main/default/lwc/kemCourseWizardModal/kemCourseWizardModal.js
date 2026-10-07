import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import getChoices from "@salesforce/apex/CatalogSetupController.getChoices";
import createCourse from "@salesforce/apex/CatalogSetupController.createCourse";
import { reduceErrors } from "c/kemUtils";

const FEE_TYPES = [
  "Tuition",
  "Admission",
  "Materials",
  "Assessment",
  "Other"
].map((v) => ({
  label: v === "Materials" ? "Kit and materials" : v,
  value: v
}));
const FREQUENCIES = [
  { label: "Monthly", value: "Monthly" },
  { label: "Per term", value: "Term" },
  { label: "One-time", value: "One-time" }
];
const ALL_BRANCHES = "";

let lineKey = 0;
const newLine = (feeType = "Tuition", frequency = "Monthly") => ({
  key: `line-${++lineKey}`,
  feeType,
  frequency,
  amount: undefined,
  branchId: ALL_BRANCHES
});

/**
 * New course: the course, its age range and its prices in one step.
 * Resolves to { courseId, addClass } or null.
 */
export default class KemCourseWizardModal extends LightningModal {
  currencyCode = CURRENCY;
  feeTypeOptions = FEE_TYPES;
  frequencyOptions = FREQUENCIES;
  branchOptions = [{ label: "All branches", value: ALL_BRANCHES }];
  canPrice = false;
  name = "";
  code = "";
  description = "";
  minAge;
  maxAge;
  pricesFrom = new Date().toISOString().slice(0, 10);
  lines = [newLine(), newLine("Admission", "One-time")];
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "New course";
  }

  async connectedCallback() {
    try {
      const choices = await getChoices();
      this.canPrice = Boolean(choices.canPrice);
      this.branchOptions = [
        { label: "All branches", value: ALL_BRANCHES },
        ...(choices.branches || []).map((b) => ({
          label: b.label,
          value: b.value
        }))
      ];
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get priceRows() {
    return this.lines.map((l, i) => ({ ...l, index: i, number: i + 1 }));
  }

  get hasPrices() {
    return this.lines.length > 0;
  }

  get noTuition() {
    return (
      this.canPrice &&
      !this.lines.some((l) => l.feeType === "Tuition" && Number(l.amount) > 0)
    );
  }

  get cannotSubmit() {
    return this.isBusy || this.isLoading || !this.name.trim();
  }

  handleField(event) {
    this[event.target.dataset.field] = event.target.value ?? "";
  }

  handleLine(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.lines = this.lines.map((l, i) => {
      return i === index ? { ...l, [field]: value } : l;
    });
  }

  handleAddLine() {
    this.lines = [...this.lines, newLine("Materials", "One-time")];
  }

  handleRemoveLine(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.lines = this.lines.filter((_, i) => i !== index);
  }

  handleCancel() {
    this.close(null);
  }

  handleCreate() {
    this.save(false);
  }

  handleCreateAndClass() {
    this.save(true);
  }

  /** Price lines left without an amount are skipped. */
  get request() {
    const toNumber = (v) => {
      return v === "" || v === undefined || v === null ? null : Number(v);
    };
    return {
      name: this.name.trim(),
      code: this.code.trim(),
      description: this.description.trim(),
      minAge: toNumber(this.minAge),
      maxAge: toNumber(this.maxAge),
      pricesFrom: this.pricesFrom || null,
      prices: this.canPrice
        ? this.lines
            .filter((l) => toNumber(l.amount))
            .map((l) => ({
              feeType: l.feeType,
              frequency: l.frequency,
              amount: Number(l.amount),
              branchId: l.branchId || null
            }))
        : []
    };
  }

  async save(addClass) {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    if (!inputs.reduce((ok, i) => i.reportValidity() && ok, true)) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const courseId = await createCourse({ request: this.request });
      this.close({ courseId, addClass });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
