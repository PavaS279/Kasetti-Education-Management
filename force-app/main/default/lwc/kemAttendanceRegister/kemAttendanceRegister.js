import { LightningElement, api } from "lwc";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getRegister from "@salesforce/apex/AttendanceController.getRegister";
import saveRegister from "@salesforce/apex/AttendanceController.saveRegister";
import {
  reduceErrors,
  toast,
  toastError,
  initials,
  toneFor,
  formatDateTime
} from "c/kemUtils";

const STATUSES = [
  { value: "Present", label: "Present", short: "P" },
  { value: "Late", label: "Late", short: "L" },
  { value: "Absent", label: "Absent", short: "A" },
  { value: "Excused", label: "Excused", short: "E" }
];

export default class KemAttendanceRegister extends LightningElement {
  @api recordId;
  register;
  marks = {};
  teacherAttendance = "Present";
  errorMessage;
  isSaving = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.register = await getRegister({ sessionId: this.recordId });
      const marks = {};
      this.register.rows.forEach((r) => {
        marks[r.learnerContactId] = {
          status: r.status,
          minutesLate: r.minutesLate,
          note: r.note
        };
      });
      this.marks = marks;
      this.teacherAttendance =
        this.register.session.Teacher_Attendance__c || "Present";
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get canEdit() {
    return (
      this.register.canMark && this.register.session.Status__c !== "Cancelled"
    );
  }
  get readOnly() {
    return !this.canEdit;
  }
  get sessionWhen() {
    return formatDateTime(this.register.session.Start__c);
  }
  get roomName() {
    return this.register.session.Room__r?.Name || "No room";
  }
  get teacherName() {
    return (
      this.register.session.Teacher_User__r?.Name || "Teacher not assigned"
    );
  }
  get isEmpty() {
    return this.register.rows.length === 0;
  }
  get teacherOptions() {
    return ["Present", "Late", "Absent", "Substituted"].map((v) => ({
      label: v,
      value: v
    }));
  }
  get saveLabel() {
    return this.register.alreadyMarked ? "Save corrections" : "Save register";
  }

  get rows() {
    return this.register.rows.map((r) => {
      const mark = this.marks[r.learnerContactId] || {};
      const rate = r.attendanceRate;
      return {
        ...r,
        ...mark,
        initials: initials(r.learnerName),
        avatarClass: `kem-avatar ${toneFor(r.learnerName)}`,
        isLate: mark.status === "Late",
        groupLabel: `Attendance for ${r.learnerName}`,
        rateLabel:
          rate === null || rate === undefined
            ? "No attendance yet"
            : `${Math.round(rate)}% attendance`,
        rateClass: r.belowThreshold
          ? "kem-badge kem-badge_danger"
          : "kem-badge",
        options: STATUSES.map((s) => ({
          ...s,
          pressed: mark.status === s.value ? "true" : "false",
          className: `choice choice_${s.value.toLowerCase()}${mark.status === s.value ? " choice_on" : ""}`
        }))
      };
    });
  }

  get counters() {
    const values = Object.values(this.marks);
    const count = (status) => values.filter((m) => m.status === status).length;
    return [
      {
        label: "Present",
        value: count("Present"),
        className: "counter counter_present"
      },
      {
        label: "Late",
        value: count("Late"),
        className: "counter counter_late"
      },
      {
        label: "Absent",
        value: count("Absent"),
        className: "counter counter_absent"
      },
      {
        label: "Excused",
        value: count("Excused"),
        className: "counter counter_excused"
      },
      {
        label: "Unmarked",
        value: values.filter((m) => !m.status).length,
        className: "counter"
      }
    ];
  }

  get unmarkedLabel() {
    const unmarked = Object.values(this.marks).filter((m) => !m.status).length;
    return unmarked
      ? `${unmarked} learner${unmarked === 1 ? "" : "s"} not marked yet`
      : "Everyone is marked";
  }

  updateMark(id, patch) {
    this.marks = { ...this.marks, [id]: { ...this.marks[id], ...patch } };
  }

  handleChoice(event) {
    this.updateMark(event.currentTarget.dataset.id, {
      status: event.currentTarget.dataset.value
    });
  }

  handleMinutes(event) {
    this.updateMark(event.target.dataset.id, {
      minutesLate: event.target.value ? Number(event.target.value) : null
    });
  }

  handleNote(event) {
    this.updateMark(event.target.dataset.id, { note: event.target.value });
  }

  handleTeacher(event) {
    this.teacherAttendance = event.detail.value;
  }

  handleAllPresent() {
    const marks = {};
    Object.keys(this.marks).forEach((id) => {
      marks[id] = {
        ...this.marks[id],
        status: this.marks[id].status || "Present"
      };
    });
    this.marks = marks;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      const rows = this.register.rows.map((r) => ({
        learnerContactId: r.learnerContactId,
        learnerAccountId: r.learnerAccountId,
        enrolmentId: r.enrolmentId,
        learnerName: r.learnerName,
        status: this.marks[r.learnerContactId]?.status || null,
        minutesLate: this.marks[r.learnerContactId]?.minutesLate || null,
        note: this.marks[r.learnerContactId]?.note || null
      }));
      await saveRegister({
        sessionId: this.recordId,
        rows,
        teacherAttendance: this.teacherAttendance
      });
      toast(
        this,
        "Attendance saved",
        "The register and attendance rates were updated."
      );
      await this.load();
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      toastError(this, error, "Attendance could not be saved");
    } finally {
      this.isSaving = false;
    }
  }
}
