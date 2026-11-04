import LightningModal from "lightning/modal";
import LightningConfirm from "lightning/confirm";
import getOverview from "@salesforce/apex/StaffSetupController.getOverview";
import assignRoles from "@salesforce/apex/StaffSetupController.assignRoles";
import endRole from "@salesforce/apex/StaffSetupController.endRole";
import { reduceErrors } from "c/kemUtils";

/** Manage staff: everyone with a KTEdutech persona, their branch roles, add or end a role. */
export default class KemStaffDirectoryModal extends LightningModal {
  overview;
  branchOptions = [];
  roleOptions = [];
  search = "";
  addingFor;
  newBranch;
  newRole;
  changed = false;
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "Manage staff";
  }

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.overview = await getOverview();
      this.branchOptions = this.overview.branches.map((b) => ({
        label: b.label,
        value: b.value
      }));
      this.roleOptions = this.overview.roles.map((r) => ({
        label: r,
        value: r
      }));
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get people() {
    const q = this.search.trim().toLowerCase();
    return (this.overview?.staff || [])
      .filter(
        (s) =>
          !q ||
          s.name.toLowerCase().includes(q) ||
          (s.email || "").toLowerCase().includes(q) ||
          s.roles.some((r) => r.branch.toLowerCase().includes(q))
      )
      .map((s) => ({
        ...s,
        noRoles: s.roles.length === 0,
        isAdding: this.addingFor === s.userId,
        statusClass: s.active ? "kem-badge kem-badge_success" : "kem-badge",
        statusLabel: s.active ? "Active" : "Inactive"
      }));
  }

  get hasPeople() {
    return this.people.length > 0;
  }

  get cannotAdd() {
    return this.isBusy || !this.newBranch || !this.newRole;
  }

  handleSearch(event) {
    this.search = event.target.value || "";
  }

  handleStartAdd(event) {
    this.addingFor = event.currentTarget.dataset.user;
    this.newBranch = this.branchOptions[0]?.value;
    this.newRole = "Teacher";
  }

  handleCancelAdd() {
    this.addingFor = undefined;
  }

  handleNewBranch(event) {
    this.newBranch = event.detail.value;
  }

  handleNewRole(event) {
    this.newRole = event.detail.value;
  }

  async handleAdd() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await assignRoles({
        userId: this.addingFor,
        roles: [{ branchId: this.newBranch, role: this.newRole }]
      });
      this.addingFor = undefined;
      this.changed = true;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async handleEnd(event) {
    const { id, label } = event.currentTarget.dataset;
    const ok = await LightningConfirm.open({
      message: `End the role ${label}? The person keeps their login and other roles; the role stays in the history.`,
      label: "End role",
      theme: "warning"
    });
    if (!ok) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await endRole({ branchStaffId: id });
      this.changed = true;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleClose() {
    this.close(this.changed);
  }
}
