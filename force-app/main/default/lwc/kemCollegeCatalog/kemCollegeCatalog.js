import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getDashboard from "@salesforce/apex/CollegeCatalogController.getDashboard";
import { reduceErrors } from "c/kemUtils";

export default class KemCollegeCatalog extends NavigationMixin(
  LightningElement
) {
  dashboard;
  errorMessage;
  isLoading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.dashboard = await getDashboard();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get cards() {
    if (!this.dashboard) return [];
    return [
      this.card("campuses", "Campuses", this.dashboard.campuses),
      this.card("programmes", "Programmes", this.dashboard.programmes),
      this.card("branches", "Branches", this.dashboard.branches),
      this.card(
        "campusBranches",
        "Campus branches",
        this.dashboard.campusBranches,
        " seats"
      ),
      this.card("sections", "Sections", this.dashboard.sections, " seats"),
      this.card("subjects", "Subjects", this.dashboard.subjects)
    ];
  }

  card(key, label, rows, metricSuffix = "") {
    return {
      key,
      label,
      count: rows?.length || 0,
      rows: (rows || []).map((row) => ({
        ...row,
        metricLabel: row.metric == null ? "" : `${row.metric}${metricSuffix}`
      }))
    };
  }

  openRecord(event) {
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
