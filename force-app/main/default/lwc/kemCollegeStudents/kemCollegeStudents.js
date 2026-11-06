import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import CURRENCY from "@salesforce/i18n/currency";
import getStudents from "@salesforce/apex/CollegeStudentsController.getStudents";
import setUsn from "@salesforce/apex/CollegeStudentsController.setUsn";
import { reduceErrors, toast } from "c/kemUtils";

const SCOPES = [
  { label: "Current students", value: "current" },
  { label: "All, including past", value: "all" }
];

const STATUS_FILTERS = [
  { label: "Any status", value: "" },
  { label: "Enrolled", value: "Enrolled" },
  { label: "Fee pending", value: "Provisional" },
  { label: "Completed", value: "Completed" },
  { label: "Discontinued", value: "Discontinued" },
  { label: "Expired", value: "Expired" },
  { label: "Cancelled", value: "Cancelled" }
];

const STATUS_LABEL = { Provisional: "Fee pending" };

function formatDate(value) {
  if (!value) {
    return "";
  }
  return new Date(`${value}T00:00:00`).toLocaleDateString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric"
  });
}

/** College Students tab: every college student with a link to their 360 page and academic record. */
export default class KemCollegeStudents extends NavigationMixin(
  LightningElement
) {
  currencyCode = CURRENCY;
  data;
  usnEditing;
  usnValue = "";
  usnReason = "";
  errorMessage;
  isLoading = true;
  scope = "current";
  campusId = "";
  status = "";
  searchTerm = "";

  scopeOptions = SCOPES;
  statusOptions = STATUS_FILTERS;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getStudents({ scope: this.scope });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get campusOptions() {
    return [
      { label: "All campuses", value: "" },
      ...(this.data?.campuses || [])
    ];
  }

  get kpis() {
    const s = this.data?.summary || {};
    return [
      { key: "enrolled", label: "Enrolled", value: s.enrolled || 0 },
      {
        key: "pending",
        label: "Fee pending",
        value: s.feePending || 0,
        className: s.feePending ? "kem-card kpi kpi_warn" : "kem-card kpi"
      },
      {
        key: "section",
        label: "Without a section",
        value: s.withoutSection || 0,
        className: s.withoutSection ? "kem-card kpi kpi_warn" : "kem-card kpi"
      }
    ].map((k) => ({ className: "kem-card kpi", ...k }));
  }

  get feesDue() {
    return this.data?.summary?.feesDue || 0;
  }

  get rows() {
    const term = this.searchTerm.trim().toLowerCase();
    return (this.data?.students || [])
      .filter((s) => !this.campusId || s.campusId === this.campusId)
      .filter((s) => !this.status || s.status === this.status)
      .filter(
        (s) =>
          !term ||
          [s.student, s.rollNumber, s.usn, s.branch, s.section]
            .filter(Boolean)
            .some((v) => v.toLowerCase().includes(term))
      )
      .map((s) => {
        const enrolled = s.status === "Enrolled";
        const pending = s.status === "Provisional";
        return {
          ...s,
          statusLabel: STATUS_LABEL[s.status] || s.status,
          statusClass: enrolled
            ? "kem-badge kem-badge_success"
            : pending
              ? "kem-badge kem-badge_warning"
              : "kem-badge",
          rollLabel:
            s.rollNumber ||
            (pending ? `pay by ${formatDate(s.paymentDueBy)}` : "—"),
          yearLabel: s.yearOfStudy ? `Year ${s.yearOfStudy}` : "",
          usnLabel: s.usn || (s.rollNumber ? "USN awaited" : "—"),
          usnClass: s.usn ? "strong" : "kem-muted",
          canEnterUsn: Boolean(this.data?.canSetUsn && s.rollNumber && !s.usn),
          canChangeUsn: Boolean(this.data?.canChangeUsn && s.usn),
          editingUsn: this.usnEditing === s.enrolmentId,
          needsReason: Boolean(s.usn),
          sectionLabel: s.section || (enrolled ? "No section yet" : "—"),
          sectionClass: !s.section && enrolled ? "warn" : "",
          portalLabel: s.hasPortal
            ? "Portal: active"
            : s.hasEmail
              ? "Portal: not given"
              : "Portal: needs an email",
          dueClass: s.feesDue > 0 ? "due" : ""
        };
      });
  }

  handleEditUsn(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.data.students.find((s) => s.enrolmentId === id);
    this.usnEditing = id;
    this.usnValue = row.usn || "";
    this.usnReason = "";
  }

  handleUsnValue(event) {
    this.usnValue = (event.target.value || "").toUpperCase();
  }

  handleUsnReason(event) {
    this.usnReason = event.target.value;
  }

  handleCancelUsn() {
    this.usnEditing = undefined;
  }

  async handleSaveUsn() {
    const id = this.usnEditing;
    try {
      await setUsn({
        enrolmentId: id,
        usn: this.usnValue,
        reason: this.usnReason
      });
      // Update the row in place (the list is cached).
      this.data = {
        ...this.data,
        students: this.data.students.map((s) => {
          if (s.enrolmentId !== id) {
            return s;
          }
          return { ...s, usn: this.usnValue };
        })
      };
      this.usnEditing = undefined;
      toast(this, "USN saved", this.usnValue, "success");
    } catch (error) {
      toast(this, "USN not saved", reduceErrors(error).join(" "), "error");
    }
  }

  get count() {
    return this.rows.length;
  }

  get isEmpty() {
    return !this.isLoading && this.data && this.rows.length === 0;
  }

  handleScope(event) {
    this.scope = event.detail.value;
    this.load();
  }

  handleCampus(event) {
    this.campusId = event.detail.value;
  }

  handleStatus(event) {
    this.status = event.detail.value;
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
  }

  handleRefresh() {
    this.load();
  }

  openStudent(event) {
    this.navigate(event.currentTarget.dataset.id, "Account");
  }

  openAdmission(event) {
    this.navigate(event.currentTarget.dataset.id, "IndividualApplication");
  }

  openRecord(event) {
    this.navigate(event.currentTarget.dataset.id, "Programme_Enrolment__c");
  }

  navigate(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }
}
