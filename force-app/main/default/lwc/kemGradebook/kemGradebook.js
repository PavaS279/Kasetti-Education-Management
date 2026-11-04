import { LightningElement, api } from "lwc";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import LightningConfirm from "lightning/confirm";
import getGradebook from "@salesforce/apex/AssessmentController.getGradebook";
import saveResults from "@salesforce/apex/AssessmentController.saveResults";
import publish from "@salesforce/apex/AssessmentController.publish";
import { reduceErrors, toast, toastError, initials, toneFor } from "c/kemUtils";

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "No date";
}

function percentOf(score, max) {
  if (score === null || score === undefined || score === "" || !max) {
    return null;
  }
  return (Number(score) / Number(max)) * 100;
}

/** Grade from bands ordered highest minimum first (mirrors AssessmentService.gradeFor). */
export function gradeFor(percent, bands) {
  if (percent === null || percent === undefined) {
    return null;
  }
  const band = (bands || []).find((b) => percent >= b.minPercent);
  return band ? band.grade : null;
}

export default class KemGradebook extends LightningElement {
  @api recordId;
  book;
  entries = {};
  errorMessage;
  isBusy = false;
  isDirty = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.book = await getGradebook({ assessmentId: this.recordId });
      const entries = {};
      this.book.rows.forEach((r) => {
        entries[r.learnerContactId] = {
          score: r.score ?? null,
          absent: r.absent === true,
          feedback: r.feedback || null
        };
      });
      this.entries = entries;
      this.isDirty = false;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get assessment() {
    return this.book.assessment;
  }
  get maxScore() {
    return this.assessment.Max_Score__c;
  }
  get isPublished() {
    return this.assessment.Status__c === "Published";
  }
  get readOnly() {
    return !this.book.canEdit;
  }
  get statusClass() {
    return this.isPublished
      ? "kem-badge kem-badge_success"
      : "kem-badge kem-badge_warning";
  }
  get dateLabel() {
    return formatDate(this.assessment.Assessment_Date__c);
  }
  get className() {
    return this.assessment.Course_Offering__r?.Name || "Class";
  }
  get typeLabel() {
    return this.assessment.Assessment_Type__c || "Assessment";
  }
  get weightLabel() {
    return this.assessment.Weight__c
      ? `${this.assessment.Weight__c}% weight`
      : null;
  }
  get isEmpty() {
    return this.book.rows.length === 0;
  }
  get readOnlyMessage() {
    return this.isPublished
      ? "Results are published and locked. Learners and guardians can now see them."
      : "You can view this gradebook. Only the class teacher or an academic coordinator can enter results.";
  }
  get bandLegend() {
    return this.book.bands
      .map((b) => `${b.grade} ≥ ${b.minPercent}%`)
      .join(" · ");
  }

  get rows() {
    return this.book.rows.map((r) => {
      const entry = this.entries[r.learnerContactId] || {};
      const pct = entry.absent ? null : percentOf(entry.score, this.maxScore);
      const grade = this.isPublished
        ? r.grade
        : entry.absent
          ? "ABS"
          : gradeFor(pct, this.book.bands);
      return {
        ...r,
        ...entry,
        initials: initials(r.learnerName),
        avatarClass: `kem-avatar ${toneFor(r.learnerName)}`,
        percentLabel: pct === null ? "—" : `${Math.round(pct * 10) / 10}%`,
        barStyle: `width:${pct === null ? 0 : Math.min(100, pct)}%`,
        grade: grade || "—",
        gradeClass: `grade ${grade ? `grade_${grade.replace("+", "plus").toLowerCase()}` : "grade_none"}`,
        scoreLabel: `Score for ${r.learnerName}`,
        absentLabel: `${r.learnerName} was absent`,
        scoreDisabled: this.readOnly || entry.absent
      };
    });
  }

  get stats() {
    const pcts = Object.values(this.entries)
      .filter((e) => !e.absent)
      .map((e) => percentOf(e.score, this.maxScore))
      .filter((p) => p !== null);
    const entered = Object.values(this.entries).filter(
      (e) => e.absent || (e.score !== null && e.score !== "")
    ).length;
    const avg = pcts.length
      ? Math.round((pcts.reduce((a, b) => a + b, 0) / pcts.length) * 10) / 10
      : null;
    return [
      { label: "Entered", value: `${entered}/${this.book.rows.length}` },
      { label: "Average", value: avg === null ? "—" : `${avg}%` },
      {
        label: "Highest",
        value: pcts.length ? `${Math.round(Math.max(...pcts))}%` : "—"
      },
      {
        label: "Lowest",
        value: pcts.length ? `${Math.round(Math.min(...pcts))}%` : "—"
      }
    ];
  }

  updateEntry(id, patch) {
    this.entries = { ...this.entries, [id]: { ...this.entries[id], ...patch } };
    this.isDirty = true;
  }

  handleScore(event) {
    const value = event.target.value;
    this.updateEntry(event.target.dataset.id, {
      score: value === "" || value === null ? null : Number(value)
    });
  }

  handleAbsent(event) {
    this.updateEntry(event.target.dataset.id, {
      absent: event.target.checked
    });
  }

  handleFeedback(event) {
    this.updateEntry(event.target.dataset.id, {
      feedback: event.target.value
    });
  }

  validInputs() {
    return [...this.template.querySelectorAll("lightning-input.score")].reduce(
      (ok, input) => input.reportValidity() && ok,
      true
    );
  }

  buildRows() {
    return this.book.rows.map((r) => {
      const entry = this.entries[r.learnerContactId] || {};
      return {
        learnerContactId: r.learnerContactId,
        enrolmentId: r.enrolmentId,
        learnerName: r.learnerName,
        score: entry.absent ? null : entry.score,
        absent: entry.absent === true,
        feedback: entry.feedback || null
      };
    });
  }

  async save() {
    await saveResults({ assessmentId: this.recordId, rows: this.buildRows() });
  }

  async handleSave() {
    if (!this.validInputs()) {
      return;
    }
    this.isBusy = true;
    try {
      await this.save();
      toast(
        this,
        "Draft saved",
        "Results are saved but not yet visible to learners."
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Results could not be saved");
    } finally {
      this.isBusy = false;
    }
  }

  async handlePublish() {
    if (!this.validInputs()) {
      return;
    }
    const confirmed = await LightningConfirm.open({
      label: "Publish results?",
      message:
        "Grades are calculated now and results become visible to learners and guardians. Published results cannot be edited.",
      theme: "warning"
    });
    if (!confirmed) {
      return;
    }
    this.isBusy = true;
    try {
      if (this.isDirty) {
        await this.save();
      }
      await publish({ assessmentId: this.recordId });
      toast(this, "Results published", "Grades are now visible to learners.");
      await this.load();
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      toastError(this, error, "Results could not be published");
    } finally {
      this.isBusy = false;
    }
  }
}
