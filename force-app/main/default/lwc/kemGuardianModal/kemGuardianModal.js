import { api } from "lwc";
import LightningModal from "lightning/modal";
import addGuardian from "@salesforce/apex/Learner360Controller.addGuardian";
import updateGuardianLink from "@salesforce/apex/Learner360Controller.updateGuardianLink";
import searchPeople from "@salesforce/apex/Learner360Controller.searchPeople";
import { reduceErrors, initials } from "c/kemUtils";

const RELATIONSHIPS = [
  "Mother",
  "Father",
  "Guardian",
  "Grandparent",
  "Sibling",
  "Other"
];
const SEARCH_DELAY = 300;

export default class KemGuardianModal extends LightningModal {
  @api label;
  @api learnerId;
  /** When set, the modal edits this existing guardian link. */
  @api link;

  mode = "new";
  searchTerm = "";
  rawResults = [];
  selectedId;
  errorMessage;
  isSaving = false;
  input = {
    isFeePayer: true,
    portalAccess: true,
    isEmergencyContact: true,
    relationship: "Guardian"
  };
  searchTimer;

  connectedCallback() {
    if (this.link) {
      this.input = {
        relationship: this.link.relationship,
        isFeePayer: this.link.isFeePayer,
        portalAccess: this.link.portalAccess,
        isEmergencyContact: this.link.isEmergencyContact
      };
    }
  }

  get isAdd() {
    return !this.link;
  }
  get isExisting() {
    return this.mode === "existing";
  }
  get modeOptions() {
    return [
      { label: "New person", value: "new" },
      { label: "Existing person", value: "existing" }
    ];
  }
  get relationshipOptions() {
    return RELATIONSHIPS.map((r) => ({ label: r, value: r }));
  }
  get results() {
    return this.rawResults.map((p) => ({
      ...p,
      initials: initials(p.Name),
      detail: [p.PersonEmail, p.PersonMobilePhone, p.KEM_Role__c]
        .filter(Boolean)
        .join(" · "),
      selected: p.Id === this.selectedId ? "true" : "false",
      className: p.Id === this.selectedId ? "result result_selected" : "result"
    }));
  }
  get isSaveDisabled() {
    if (this.isSaving) {
      return true;
    }
    if (!this.isAdd) {
      return false;
    }
    return this.isExisting ? !this.selectedId : !this.input.lastName;
  }

  handleMode(event) {
    this.mode = event.detail.value;
  }

  handleField(event) {
    this.input = { ...this.input, [event.target.name]: event.detail.value };
  }

  handleToggle(event) {
    this.input = { ...this.input, [event.target.name]: event.target.checked };
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
    clearTimeout(this.searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.runSearch(), SEARCH_DELAY);
  }

  async runSearch() {
    try {
      this.rawResults = await searchPeople({ term: this.searchTerm });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  handlePick(event) {
    this.selectedId = event.currentTarget.dataset.id;
  }

  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      if (this.isAdd) {
        const payload = {
          ...this.input,
          existingAccountId: this.isExisting ? this.selectedId : null
        };
        await addGuardian({ learnerAccountId: this.learnerId, input: payload });
      } else {
        await updateGuardianLink({
          relationId: this.link.relationId,
          input: this.input
        });
      }
      this.close("saved");
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isSaving = false;
    }
  }
}
