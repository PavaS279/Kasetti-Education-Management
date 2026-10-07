import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getCentre from "@salesforce/apex/SetupCentreController.getCentre";
import { reduceErrors } from "c/kemUtils";

/**
 * Set-up Centre: counts, create buttons and set-up gaps for administrators,
 * branch managers and academic coordinators. Hidden for everyone else.
 * "New" opens the record form for now; later stages swap in guided screens.
 */
export default class KemSetupCentre extends NavigationMixin(LightningElement) {
  centre;
  errorMessage;
  hidden = false;
  isLoading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.centre = await getCentre();
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    } finally {
      this.isLoading = false;
    }
  }

  get visible() {
    return !this.hidden;
  }

  get tiles() {
    return (this.centre?.tiles || []).map((t) => ({
      ...t,
      canList: Boolean(t.objectApiName)
    }));
  }

  get gapRows() {
    return (this.centre?.gaps || [])
      .filter((g) => g.count > 0)
      .map((g) => ({
        ...g,
        more: g.count > g.records.length ? g.count - g.records.length : 0
      }));
  }

  get hasGaps() {
    return this.gapRows.length > 0;
  }

  get gapBadgeLabel() {
    const n = this.centre?.openGaps || 0;
    return n ? `${n} to fix` : "All set";
  }

  get gapBadgeClass() {
    return this.centre?.openGaps
      ? "kem-badge kem-badge_warning"
      : "kem-badge kem-badge_success";
  }

  tileFor(key) {
    return (this.centre?.tiles || []).find((t) => t.key === key);
  }

  handleRefresh() {
    this.load();
  }

  handleCreate(event) {
    const tile = this.tileFor(event.currentTarget.dataset.key);
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: tile.objectApiName, actionName: "new" }
    });
  }

  handleList(event) {
    const tile = this.tileFor(event.currentTarget.dataset.key);
    const pageRef = {
      type: "standard__objectPage",
      attributes: { objectApiName: tile.objectApiName, actionName: "list" }
    };
    if (tile.listView) {
      pageRef.state = { filterName: tile.listView };
    }
    this[NavigationMixin.Navigate](pageRef);
  }

  handleOpenRecord(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
