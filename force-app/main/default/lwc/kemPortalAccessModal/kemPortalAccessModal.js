import { api } from "lwc";
import LightningModal from "lightning/modal";
import getFamily from "@salesforce/apex/PortalAccessController.getFamily";
import prepareAccess from "@salesforce/apex/PortalAccessController.prepareAccess";
import giveAccess from "@salesforce/apex/PortalAccessController.giveAccess";
import searchPeople from "@salesforce/apex/Learner360Controller.searchPeople";
import { reduceErrors } from "c/kemUtils";

/**
 * Portal access for a family: everyone linked to the person, their login
 * status, and "Give access", which creates the login and sends the welcome
 * email at once. Without a person, a search comes first.
 * Resolves to the number of logins given.
 */
export default class KemPortalAccessModal extends LightningModal {
  @api accountId;
  selectedId;
  family;
  results = [];
  term = "";
  given = 0;
  givenMessage;
  errorMessage;
  busyId;
  isLoading = false;

  get heading() {
    return "Portal access";
  }

  connectedCallback() {
    if (this.accountId) {
      this.selectedId = this.accountId;
      this.load();
    }
  }

  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.family = await getFamily({ accountId: this.selectedId });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get canChangePerson() {
    return !this.accountId;
  }

  get isSearching() {
    return !this.selectedId;
  }

  get people() {
    return (this.family?.people || []).map((p) => {
      let status = "No login";
      let statusClass = "kem-badge";
      if (p.hasLogin) {
        status = p.active ? "Has a login" : "Login deactivated";
        statusClass = p.active
          ? "kem-badge kem-badge_success"
          : "kem-badge kem-badge_warning";
      }
      return {
        ...p,
        status,
        statusClass,
        showReason: !p.canGive && !p.hasLogin && Boolean(p.reason),
        isBusy: this.busyId === p.accountId
      };
    });
  }

  get licenceText() {
    const n = this.family?.freeLicences ?? 0;
    return `${n} portal licence${n === 1 ? "" : "s"} free`;
  }

  get noPermission() {
    return this.family && !this.family.canGive;
  }

  async handleSearch(event) {
    this.term = event.target.value || "";
    if (this.term.trim().length < 2) {
      this.results = [];
      return;
    }
    try {
      const found = await searchPeople({ term: this.term.trim() });
      this.results = (found || []).map((a) => ({
        id: a.Id,
        name: a.Name,
        detail: [a.KEM_Role__c, a.PersonEmail].filter(Boolean).join(" · ")
      }));
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  handlePick(event) {
    this.selectedId = event.currentTarget.dataset.id;
    this.results = [];
    this.load();
  }

  handleChangePerson() {
    this.selectedId = undefined;
    this.family = undefined;
  }

  async handleGive(event) {
    const id = event.currentTarget.dataset.id;
    this.busyId = id;
    this.errorMessage = undefined;
    this.givenMessage = undefined;
    try {
      // Users and data cannot be saved together: the owner check runs first.
      await prepareAccess({ accountId: id });
      const result = await giveAccess({ accountId: id });
      this.given++;
      this.givenMessage = `Login created (${result.username}). The welcome email with the link to set a password has been sent.`;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.busyId = undefined;
    }
  }

  handleClose() {
    this.close(this.given);
  }
}
