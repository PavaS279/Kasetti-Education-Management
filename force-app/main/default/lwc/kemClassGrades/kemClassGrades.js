import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import LightningConfirm from "lightning/confirm";
import getClassGrades from "@salesforce/apex/GradingController.getClassGrades";
import saveWeights from "@salesforce/apex/GradingController.saveWeights";
import saveComments from "@salesforce/apex/GradingController.saveComments";
import finaliseGrades from "@salesforce/apex/GradingController.finaliseGrades";
import reopenGrades from "@salesforce/apex/GradingController.reopenGrades";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const GRADE_CLASS = {
  "A+": "grade grade_top",
  A: "grade grade_top",
  B: "grade grade_good",
  C: "grade grade_mid",
  D: "grade grade_low",
  F: "grade grade_fail"
};

const shortDate = (value) =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        day: "numeric",
        month: "short"
      }).format(new Date(value))
    : "";

/** Class gradebook: weights, results, weighted course grades, comments and report cards. */
export default class KemClassGrades extends NavigationMixin(LightningElement) {
  @api recordId;
  data;
  errorMessage;
  weights = {};
  comments = {};
  dirtyWeights = false;
  dirtyComments = false;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getClassGrades({ offeringId: this.recordId });
      this.weights = {};
      this.comments = {};
      this.dirtyWeights = false;
      this.dirtyComments = false;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get isFinal() {
    return this.data.status === "Final";
  }
  get editable() {
    return this.data.canEdit && !this.isFinal;
  }
  get statusClass() {
    return this.isFinal
      ? "kem-badge kem-badge_success"
      : "kem-badge kem-badge_info";
  }
  get statusLabel() {
    return this.isFinal ? "Final" : "Provisional";
  }
  get finalisedText() {
    if (!this.isFinal || !this.data.finalisedOn) {
      return "";
    }
    return `Finalised ${shortDate(this.data.finalisedOn)} by ${this.data.finalisedBy}`;
  }
  get hasColumns() {
    return this.data.columns.length > 0;
  }
  get hasRows() {
    return this.data.rows.length > 0;
  }
  get weightNote() {
    return this.data.equalWeights
      ? "All published assessments count equally. Enter weights to change that."
      : "Assessments without a weight do not count.";
  }
  get columns() {
    return this.data.columns.map((c) => ({
      ...c,
      dateLabel: shortDate(c.assessmentDate),
      weightValue: this.weights[c.assessmentId] ?? c.weight,
      shareLabel: c.published
        ? c.share == null
          ? "not counted"
          : `${c.share}% of grade`
        : "draft",
      headClass: `col${c.published ? "" : " col_draft"}`
    }));
  }
  get rows() {
    return this.data.rows.map((r) => ({
      ...r,
      scoreLabel: r.score == null ? "—" : `${Number(r.score).toFixed(1)}%`,
      gradeClass: GRADE_CLASS[r.grade] || "grade",
      gradeLabel: r.grade || "—",
      attendanceLabel:
        r.attendance == null ? "—" : `${Number(r.attendance).toFixed(0)}%`,
      commentValue: this.comments[r.enrolmentId] ?? r.comment ?? "",
      cells: r.cells.map((c) => ({
        ...c,
        key: `${r.enrolmentId}-${c.assessmentId}`,
        label: c.absent
          ? "Absent"
          : c.percent == null
            ? "—"
            : `${Number(c.percent).toFixed(0)}%`,
        cellClass: `cell${c.absent ? " cell_absent" : ""}`
      })),
      hasReportCard: !!r.reportCardId
    }));
  }
  get averageLabel() {
    return this.data.classAverage == null ? "—" : `${this.data.classAverage}%`;
  }
  get canFinalise() {
    return this.editable && this.hasColumns && this.hasRows;
  }
  get canReopen() {
    return this.isFinal && this.data.canReopen;
  }
  get draftWarning() {
    return this.data.draftAssessments > 0 && !this.isFinal
      ? `${this.data.draftAssessments} draft assessment(s) must be published or deleted before finalising.`
      : null;
  }

  handleWeight(event) {
    const id = event.target.dataset.id;
    const value = event.target.value;
    this.weights = {
      ...this.weights,
      [id]: value === "" || value == null ? null : Number(value)
    };
    this.dirtyWeights = true;
  }

  handleComment(event) {
    const id = event.target.dataset.id;
    this.comments = { ...this.comments, [id]: event.target.value };
    this.dirtyComments = true;
  }

  async run(action, title, message) {
    this.isBusy = true;
    try {
      const result = await action();
      toast(
        this,
        title,
        typeof message === "function" ? message(result) : message
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  handleSaveWeights() {
    const weights = this.data.columns.map((c) => ({
      assessmentId: c.assessmentId,
      weight:
        this.weights[c.assessmentId] !== undefined
          ? this.weights[c.assessmentId]
          : c.weight
    }));
    this.run(
      () => saveWeights({ offeringId: this.recordId, weights }),
      "Weights saved",
      "Course grades were recalculated."
    );
  }

  handleSaveComments() {
    const comments = Object.keys(this.comments).map((enrolmentId) => ({
      enrolmentId,
      comment: this.comments[enrolmentId]
    }));
    this.run(
      () => saveComments({ offeringId: this.recordId, comments }),
      "Comments saved",
      "They will appear on the report cards."
    );
  }

  async handleFinalise() {
    const confirmed = await LightningConfirm.open({
      label: "Finalise grades",
      message:
        "Grades are locked, a report card is issued for every learner and families are notified. Continue?",
      theme: "warning"
    });
    if (!confirmed) {
      return;
    }
    this.run(
      () => finaliseGrades({ offeringId: this.recordId }),
      "Grades finalised",
      (count) => `${count} report cards are being issued.`
    );
  }

  async handleReopen() {
    const reason = await ReasonModal.open({
      size: "small",
      label: "Reopen grades",
      message:
        "Grades become provisional again and issued report cards are marked superseded.",
      confirmLabel: "Reopen"
    });
    if (reason) {
      this.run(
        () => reopenGrades({ offeringId: this.recordId, reason }),
        "Grades reopened",
        "Finalise again to issue new report cards."
      );
    }
  }

  handleReportCard(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__namedPage",
      attributes: { pageName: "filePreview" },
      state: { selectedRecordId: event.currentTarget.dataset.id }
    });
  }
}
