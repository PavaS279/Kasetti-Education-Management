import { api } from "lwc";
import LightningModal from "lightning/modal";
import recordAbsence from "@salesforce/apex/CoverController.recordAbsence";
import { reduceErrors } from "c/kemUtils";

const REASONS = [
  "Sick Leave",
  "Planned Leave",
  "Training",
  "Personal",
  "Other"
].map((r) => ({ label: r, value: r }));

function atHour(days, hour) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
}

/** Reports a teacher absence. Resolves to the absence Id, or null. */
export default class KemAbsenceModal extends LightningModal {
  @api teachers = [];
  @api canArrange = false;
  reasonOptions = REASONS;
  teacherId = "";
  startAt = atHour(0, 0);
  endAt = atHour(0, 23);
  reason = "Sick Leave";
  notes = "";
  errorMessage;
  isBusy = false;

  get teacherOptions() {
    return [
      { label: "Me", value: "" },
      ...this.teachers.map((t) => ({ label: t.Name, value: t.Id }))
    ];
  }
  get cannotSave() {
    return this.isBusy || !this.startAt || !this.endAt || !this.reason;
  }

  handleTeacher(event) {
    this.teacherId = event.detail.value;
  }
  handleStart(event) {
    this.startAt = event.target.value;
  }
  handleEnd(event) {
    this.endAt = event.target.value;
  }
  handleReason(event) {
    this.reason = event.detail.value;
  }
  handleNotes(event) {
    this.notes = event.target.value || "";
  }
  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const absenceId = await recordAbsence({
        request: {
          teacherId: this.teacherId || null,
          startAt: this.startAt,
          endAt: this.endAt,
          reason: this.reason,
          notes: this.notes.trim()
        }
      });
      this.close(absenceId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
