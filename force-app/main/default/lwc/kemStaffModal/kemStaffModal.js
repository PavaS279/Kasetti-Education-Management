import LightningModal from "lightning/modal";
import getOverview from "@salesforce/apex/StaffSetupController.getOverview";
import createLogin from "@salesforce/apex/StaffSetupController.createLogin";
import assignRoles from "@salesforce/apex/StaffSetupController.assignRoles";
import { reduceErrors } from "c/kemUtils";

let roleKey = 0;
const newRole = (branchId = "", role = "") => ({
  key: `role-${++roleKey}`,
  branchId,
  role
});

/**
 * Add staff member (administrators): the login with its licence, persona and
 * AI access, then the branch roles. Saving is two steps because Salesforce
 * keeps users and data apart; if the roles fail, the login stays and the
 * roles can be retried. Resolves to { userId, roles } or null.
 */
export default class KemStaffModal extends LightningModal {
  overview;
  personaOptions = [];
  branchOptions = [];
  roleOptions = [];
  form = {
    firstName: "",
    lastName: "",
    email: "",
    mobile: "",
    persona: "KEM_Teacher_Persona",
    aiUser: false,
    sendEmail: true,
    username: ""
  };
  usernameEdited = false;
  roles = [newRole()];
  createdUserId;
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "Add staff member";
  }

  async connectedCallback() {
    try {
      this.overview = await getOverview();
      this.personaOptions = this.overview.personas.map((p) => ({
        label: p.label,
        value: p.value
      }));
      this.branchOptions = this.overview.branches.map((b) => ({
        label: b.label,
        value: b.value
      }));
      this.roleOptions = this.overview.roles.map((r) => ({
        label: r,
        value: r
      }));
      this.roles = [newRole(this.branchOptions[0]?.value || "", "Teacher")];
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get freeUsers() {
    return this.overview?.freeUserLicences ?? 0;
  }
  get freeEducation() {
    return this.overview?.freeEducationLicences ?? 0;
  }
  get noLicences() {
    return (
      Boolean(this.overview) && (this.freeUsers < 1 || this.freeEducation < 1)
    );
  }
  get licenceText() {
    return `${this.freeUsers} Salesforce and ${this.freeEducation} Education Cloud licences free`;
  }
  get licenceClass() {
    return this.noLicences ? "licence licence_bad" : "licence";
  }
  get isAdministrator() {
    return this.form.persona === "KEM_Administrator_Persona";
  }
  get roleRows() {
    return this.roles.map((r, index) => ({
      ...r,
      index,
      canRemove: this.roles.length > 1
    }));
  }
  get rolesSaved() {
    return Boolean(this.createdUserId);
  }
  get submitLabel() {
    return this.createdUserId ? "Save the branch roles" : "Add staff member";
  }
  get cannotSubmit() {
    return (
      this.isBusy ||
      this.isLoading ||
      (!this.createdUserId &&
        (this.noLicences ||
          !this.form.lastName.trim() ||
          !this.form.email.trim()))
    );
  }

  suggestedUsername(email) {
    return email
      ? `${email.trim().toLowerCase()}${this.overview?.usernameSuffix || ""}`
      : "";
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
    const form = { ...this.form, [field]: value };
    if (field === "email" && !this.usernameEdited) {
      form.username = this.suggestedUsername(value);
    }
    if (field === "username") {
      this.usernameEdited = true;
    }
    if (field === "persona") {
      const role = this.overview.personas.find(
        (p) => p.value === value
      )?.detail;
      if (role) {
        this.roles = this.roles.map((r) => ({ ...r, role }));
      }
    }
    this.form = form;
  }

  handleRole(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    this.roles = this.roles.map((r, i) => {
      return i === index ? { ...r, [field]: event.detail.value } : r;
    });
  }

  handleAddRole() {
    const role = this.overview.personas.find(
      (p) => p.value === this.form.persona
    )?.detail;
    this.roles = [...this.roles, newRole("", role || "")];
  }

  handleRemoveRole(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.roles = this.roles.filter((_, i) => i !== index);
  }

  handleCancel() {
    this.close(
      this.createdUserId ? { userId: this.createdUserId, roles: 0 } : null
    );
  }

  async handleSubmit() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    if (
      !this.createdUserId &&
      !inputs.reduce((ok, i) => i.reportValidity() && ok, true)
    ) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      if (!this.createdUserId) {
        this.createdUserId = await createLogin({
          request: {
            firstName: this.form.firstName.trim(),
            lastName: this.form.lastName.trim(),
            email: this.form.email.trim(),
            mobile: this.form.mobile.trim(),
            persona: this.form.persona,
            aiUser: this.form.aiUser,
            sendEmail: this.form.sendEmail,
            username: this.form.username.trim()
          }
        });
      }
      const lines = this.roles
        .filter((r) => r.branchId && r.role)
        .map((r) => ({ branchId: r.branchId, role: r.role }));
      const added = lines.length
        ? await assignRoles({ userId: this.createdUserId, roles: lines })
        : 0;
      this.close({ userId: this.createdUserId, roles: added });
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.errorMessage = this.createdUserId
        ? `The login was created, but the branch roles were not saved: ${message} Change them and save again.`
        : message;
    } finally {
      this.isBusy = false;
    }
  }
}
