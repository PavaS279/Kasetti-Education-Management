import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import getOverview from "@salesforce/apex/DiscountSetupController.getOverview";
import setActive from "@salesforce/apex/DiscountSetupController.setActive";
import { reduceErrors } from "c/kemUtils";

const formatDate = (value) =>
  new Date(`${value}T00:00:00`).toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric"
  });

const STATUS_CLASS = {
  Active: "kem-badge kem-badge_success",
  Scheduled: "kem-badge",
  Expired: "kem-badge kem-badge_warning",
  "Used up": "kem-badge kem-badge_warning",
  Inactive: "kem-badge"
};

/** Discounts: every code with how it is used; new, edit, switch on or off. Resolves to true if anything changed. */
export default class KemDiscountManagerModal extends LightningModal {
  currencyCode = CURRENCY;
  overview;
  editing;
  isNew = false;
  showInactive = false;
  changed = false;
  errorMessage;
  isLoading = true;

  get heading() {
    return "Discounts";
  }

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.overview = await getOverview();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get isForm() {
    return this.isNew || Boolean(this.editing);
  }
  get canEdit() {
    return Boolean(this.overview?.canEdit);
  }
  get rows() {
    return (this.overview?.discounts || [])
      .filter((d) => this.showInactive || d.status !== "Inactive")
      .map((d) => ({
        ...d,
        statusClass: STATUS_CLASS[d.status] || "kem-badge",
        valueText:
          d.discountType === "Percentage"
            ? `${Number(d.value)}% off`
            : `₹${Number(d.value).toLocaleString("en-IN")} off`,
        scope: [
          d.feeType || "Any fee",
          d.branch || "All branches",
          d.course || "All courses"
        ].join(" · "),
        usage: d.maxUses
          ? `${d.timesUsed} of ${d.maxUses} used`
          : `${d.timesUsed} used`,
        dates: [
          d.validFrom ? `from ${formatDate(d.validFrom)}` : "",
          d.validTo ? `until ${formatDate(d.validTo)}` : ""
        ]
          .filter(Boolean)
          .join(" "),
        toggleLabel: d.active ? "Switch off" : "Switch on",
        hasPending: d.pendingApprovals > 0
      }));
  }
  get hasRows() {
    return this.rows.length > 0;
  }
  get inactiveCount() {
    return (this.overview?.discounts || []).filter(
      (d) => d.status === "Inactive"
    ).length;
  }

  handleShowInactive(event) {
    this.showInactive = event.target.checked;
  }

  handleNew() {
    this.isNew = true;
    this.editing = undefined;
  }

  handleEdit(event) {
    const id = event.currentTarget.dataset.id;
    this.editing = this.overview.discounts.find((d) => d.id === id);
    this.isNew = false;
  }

  handleFormCancel() {
    this.isNew = false;
    this.editing = undefined;
  }

  async handleSaved() {
    this.isNew = false;
    this.editing = undefined;
    this.changed = true;
    await this.load();
  }

  async handleToggle(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.overview.discounts.find((d) => d.id === id);
    this.errorMessage = undefined;
    try {
      await setActive({ discountId: id, active: !row.active });
      this.changed = true;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  handleClose() {
    this.close(this.changed);
  }
}
