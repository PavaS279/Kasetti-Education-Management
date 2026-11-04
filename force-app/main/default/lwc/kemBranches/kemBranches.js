import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import CURRENCY from "@salesforce/i18n/currency";
import getOverview from "@salesforce/apex/BranchController.getOverview";
import BranchCloneModal from "c/kemBranchCloneModal";
import { reduceErrors, toast } from "c/kemUtils";

const SORTS = [
  { label: "Name", value: "name" },
  { label: "Fill rate", value: "fillRate" },
  { label: "Attendance", value: "attendanceRate" },
  { label: "Learners", value: "learners" },
  { label: "Outstanding fees", value: "outstanding" }
];

function percent(value) {
  return value === null || value === undefined ? "—" : `${value}%`;
}

/** Branch comparison with "open a new branch from this one". */
export default class KemBranches extends NavigationMixin(LightningElement) {
  @api recordId;
  data;
  errorMessage;
  hidden = false;
  sortBy = "name";
  sortOptions = SORTS;
  currencyCode = CURRENCY;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getOverview();
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      // Users without access to branch figures simply do not see the panel.
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.errorMessage;
  }
  get title() {
    return this.recordId ? "Branch comparison" : "Branches";
  }
  get hasBranches() {
    return this.data?.branches.length > 0;
  }
  get canClone() {
    return this.data?.canCreateBranch;
  }
  get showCloneThis() {
    return this.recordId && this.canClone;
  }
  get showFinance() {
    return this.data?.showFinance;
  }
  get totals() {
    const t = this.data.totals;
    return [
      { key: "branches", label: "Branches", value: this.data.branches.length },
      { key: "classes", label: "Active classes", value: t.activeClasses },
      { key: "fill", label: "Fill rate", value: percent(t.fillRate) },
      { key: "learners", label: "Learners", value: t.learners },
      {
        key: "attendance",
        label: "Attendance (30 days)",
        value: percent(t.attendanceRate)
      },
      { key: "enquiries", label: "Open enquiries", value: t.openEnquiries }
    ];
  }
  get branches() {
    const key = this.sortBy;
    const rows = [...this.data.branches].sort((a, b) => {
      if (key === "name") {
        return (a.name || "").localeCompare(b.name || "");
      }
      return (b[key] ?? -1) - (a[key] ?? -1);
    });
    return rows.map((b) => {
      const fill = Math.min(Number(b.fillRate) || 0, 100);
      const current = b.branchId === this.recordId;
      return {
        ...b,
        className: `branch${current ? " branch_current" : ""}${
          b.active ? "" : " branch_inactive"
        }`,
        subtitle: [b.code, b.city].filter(Boolean).join(" · "),
        fill: percent(b.fillRate),
        fillStyle: `width: ${fill}%`,
        fillClass: `bar-fill${fill >= 90 ? " bar-fill_high" : ""}`,
        attendance: percent(b.attendanceRate),
        attendanceClass: `metric-value${
          b.attendanceRate !== null &&
          b.attendanceRate !== undefined &&
          b.attendanceRate < 80
            ? " metric-value_warn"
            : ""
        }`,
        overdueClass: `metric-value${b.overdue > 0 ? " metric-value_warn" : ""}`,
        classes: `${b.activeClasses}${
          b.plannedClasses ? ` + ${b.plannedClasses} planned` : ""
        }`,
        current,
        inactive: !b.active
      };
    });
  }

  handleSort(event) {
    this.sortBy = event.detail.value;
  }
  handleRefresh() {
    this.load();
  }

  handleOpen(event) {
    event.preventDefault();
    this.navigateTo(event.currentTarget.dataset.id);
  }

  handleCloneThis() {
    this.cloneFrom(this.recordId);
  }
  handleClone(event) {
    this.cloneFrom(event.currentTarget.dataset.id);
  }

  async cloneFrom(branchId) {
    const newBranchId = await BranchCloneModal.open({
      size: "medium",
      branchId
    });
    if (newBranchId) {
      toast(this, "Branch opened", "The new branch is ready for review.");
      await this.load();
      this.navigateTo(newBranchId);
    }
  }

  navigateTo(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, actionName: "view" }
    });
  }
}
