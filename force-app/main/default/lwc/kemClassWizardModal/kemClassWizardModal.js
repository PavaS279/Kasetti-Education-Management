import { api } from "lwc";
import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/CatalogSetupController.getChoices";
import getBranchChoices from "@salesforce/apex/CatalogSetupController.getBranchChoices";
import previewClass from "@salesforce/apex/CatalogSetupController.previewClass";
import createClass from "@salesforce/apex/CatalogSetupController.createClass";
import createFaculty from "@salesforce/apex/CatalogSetupController.createFaculty";
import { reduceErrors } from "c/kemUtils";

const STEPS = [
  { value: "details", label: "Class" },
  { value: "people", label: "Room and teacher" },
  { value: "timetable", label: "Timetable" },
  { value: "preview", label: "Check and create" }
];
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MODES = ["Classroom", "Online", "Hybrid"].map((v) => ({
  label: v,
  value: v
}));
const LENGTHS = [45, 60, 75, 90, 120, 180].map((m) => ({
  label:
    m < 60 || m % 60 ? `${m} minutes` : `${m / 60} hour${m > 60 ? "s" : ""}`,
  value: String(m)
}));
const NONE = "";
const MAX_CLASHES = 8;

const isoDate = (d) => {
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
};

let patternKey = 0;
const newPattern = () => ({
  key: `p-${++patternKey}`,
  days: [],
  startTime: "16:30",
  minutes: "60"
});

/**
 * New class: course and branch, room and teacher, weekly times and term
 * dates, then a preview of the sessions (holidays skipped, clashes) before
 * anything is saved. Resolves to { classId, sessions } or null.
 */
export default class KemClassWizardModal extends LightningModal {
  @api courseId;
  @api branchId;

  steps = STEPS;
  step = "details";
  modeOptions = MODES;
  lengthOptions = LENGTHS;
  courseOptions = [];
  branchOptions = [];
  facultyOptions = [];
  roomOptions = [];
  teacherOptions = [];
  rooms = [];
  canCreateFaculty = false;

  form = {
    courseId: undefined,
    branchId: undefined,
    name: "",
    section: "",
    deliveryMode: "Classroom",
    capacity: 12,
    openForEnrolment: true,
    roomId: NONE,
    teacherUserId: NONE,
    facultyId: NONE,
    startDate: isoDate(new Date()),
    endDate: isoDate(new Date(Date.now() + 90 * 86400000))
  };
  patterns = [newPattern()];

  showFacultyForm = false;
  faculty = { firstName: "", lastName: "", email: "", subject: "" };

  loadedBranch;
  preview;
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "New class";
  }

  async connectedCallback() {
    this.form = {
      ...this.form,
      courseId: this.courseId,
      branchId: this.branchId
    };
    try {
      await this.loadChoices();
      if (this.form.branchId) {
        await this.loadBranch();
        this.loadedBranch = this.form.branchId;
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  async loadChoices() {
    const choices = await getChoices();
    const opts = (list) =>
      (list || []).map((o) => ({ label: o.label, value: o.value }));
    this.courseOptions = opts(choices.courses);
    this.branchOptions = opts(choices.branches);
    this.facultyOptions = [
      { label: "None", value: NONE },
      ...(choices.faculty || []).map((o) => ({
        label: o.detail
          ? `${o.label} (${o.detail.replace(/^Faculty – /, "")})`
          : o.label,
        value: o.value
      }))
    ];
    this.canCreateFaculty = Boolean(choices.canCreateFaculty);
  }

  async loadBranch() {
    const c = await getBranchChoices({ branchId: this.form.branchId });
    this.rooms = c.rooms || [];
    this.roomOptions = [
      { label: "No room", value: NONE },
      ...this.rooms.map((r) => ({ label: r.label, value: r.value }))
    ];
    this.teacherOptions = [
      { label: "None", value: NONE },
      ...(c.teachers || []).map((t) => ({ label: t.label, value: t.value }))
    ];
  }

  // ------------------------------------------------------------ steps

  get stepIndex() {
    return STEPS.findIndex((s) => s.value === this.step);
  }
  get isDetails() {
    return this.step === "details";
  }
  get isPeople() {
    return this.step === "people";
  }
  get isTimetable() {
    return this.step === "timetable";
  }
  get isPreview() {
    return this.step === "preview";
  }
  get showBack() {
    return this.stepIndex > 0;
  }
  get cannotCreate() {
    return this.isBusy || !this.preview || !this.preview.sessions;
  }

  get stepProblem() {
    const f = this.form;
    if (this.isDetails) {
      if (!f.courseId) return "Choose the course.";
      if (!f.branchId) return "Choose the branch.";
      if (!(Number(f.capacity) >= 1)) return "Enter the number of seats.";
    }
    if (this.isPeople && this.roomTooSmall) {
      return `${this.selectedRoom.label.replace(/ \(.*/, "")} seats ${this.selectedRoomSeats}; reduce the class size or choose a bigger room.`;
    }
    if (this.isTimetable) {
      if (!f.startDate || !f.endDate) return "Enter the first and last day.";
      if (f.endDate < f.startDate)
        return "The last day cannot be before the first.";
      if (this.patterns.some((p) => !p.days.length))
        return "Choose the day(s) for every weekly time.";
      if (this.patterns.some((p) => !p.startTime))
        return "Enter a start time for every weekly time.";
    }
    return undefined;
  }

  async handleNext() {
    this.errorMessage = this.stepProblem;
    if (this.errorMessage) {
      return;
    }
    if (this.isDetails && this.loadedBranch !== this.form.branchId) {
      this.isBusy = true;
      try {
        await this.loadBranch();
        this.loadedBranch = this.form.branchId;
      } catch (error) {
        this.errorMessage = reduceErrors(error).join(" ");
        return;
      } finally {
        this.isBusy = false;
      }
    }
    this.step = STEPS[this.stepIndex + 1].value;
    if (this.isPreview) {
      await this.runPreview();
    }
  }

  handleBack() {
    this.errorMessage = undefined;
    this.step = STEPS[this.stepIndex - 1].value;
  }

  handleCancel() {
    this.close(null);
  }

  // ------------------------------------------------------------ fields

  handleField(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.detail?.value !== undefined
          ? event.detail.value
          : event.target.value;
    if (field === "branchId" && value !== this.form.branchId) {
      this.form = { ...this.form, roomId: NONE, teacherUserId: NONE };
    }
    this.form = { ...this.form, [field]: value };
    this.preview = undefined;
  }

  get selectedRoom() {
    return this.rooms.find((r) => r.value === this.form.roomId);
  }
  get selectedRoomSeats() {
    return this.selectedRoom?.detail
      ? Math.round(Number(this.selectedRoom.detail))
      : null;
  }
  get roomTooSmall() {
    return (
      this.selectedRoomSeats !== null &&
      Number(this.form.capacity) > this.selectedRoomSeats
    );
  }
  get noRoomsAtBranch() {
    return this.roomOptions.length <= 1;
  }
  get noTeachersAtBranch() {
    return this.teacherOptions.length <= 1;
  }
  get isOnline() {
    return this.form.deliveryMode === "Online";
  }

  // ------------------------------------------------------------ faculty

  handleShowFaculty() {
    this.showFacultyForm = true;
  }
  handleHideFaculty() {
    this.showFacultyForm = false;
  }
  handleFacultyField(event) {
    this.faculty = {
      ...this.faculty,
      [event.target.dataset.field]: event.target.value || ""
    };
  }
  get cannotAddFaculty() {
    return this.isBusy || !this.faculty.lastName.trim();
  }
  async handleAddFaculty() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const id = await createFaculty({
        request: {
          firstName: this.faculty.firstName.trim(),
          lastName: this.faculty.lastName.trim(),
          email: this.faculty.email.trim(),
          subject: this.faculty.subject.trim()
        }
      });
      await this.loadChoices();
      this.form = { ...this.form, facultyId: id };
      this.faculty = { firstName: "", lastName: "", email: "", subject: "" };
      this.showFacultyForm = false;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  // ------------------------------------------------------------ patterns

  get patternRows() {
    return this.patterns.map((p, index) => ({
      ...p,
      index,
      number: index + 1,
      canRemove: this.patterns.length > 1,
      timeValue: `${p.startTime}:00.000`,
      chips: DAYS.map((d) => {
        const on = p.days.includes(d);
        return {
          value: d,
          pressed: on ? "true" : "false",
          cls: on ? "chip chip_on" : "chip"
        };
      })
    }));
  }

  updatePattern(index, change) {
    this.patterns = this.patterns.map((p, i) => {
      return i === index ? { ...p, ...change } : p;
    });
    this.preview = undefined;
  }

  handleDay(event) {
    const index = Number(event.currentTarget.dataset.index);
    const day = event.currentTarget.dataset.day;
    const days = this.patterns[index].days;
    this.updatePattern(index, {
      days: days.includes(day) ? days.filter((d) => d !== day) : [...days, day]
    });
  }

  handleTime(event) {
    const value = event.target.value || "";
    this.updatePattern(Number(event.target.dataset.index), {
      startTime: value.slice(0, 5)
    });
  }

  handleLength(event) {
    this.updatePattern(Number(event.target.dataset.index), {
      minutes: event.detail.value
    });
  }

  handleAddPattern() {
    this.patterns = [...this.patterns, newPattern()];
    this.preview = undefined;
  }

  handleRemovePattern(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.patterns = this.patterns.filter((_, i) => i !== index);
    this.preview = undefined;
  }

  // ------------------------------------------------------------ preview and create

  get request() {
    const f = this.form;
    return {
      courseId: f.courseId,
      branchId: f.branchId,
      name: f.name.trim(),
      section: f.section.trim(),
      deliveryMode: f.deliveryMode,
      roomId: f.roomId || null,
      capacity: Number(f.capacity),
      teacherUserId: f.teacherUserId || null,
      facultyId: f.facultyId || null,
      startDate: f.startDate,
      endDate: f.endDate,
      openForEnrolment: f.openForEnrolment,
      patterns: this.patterns.map((p) => ({
        days: DAYS.filter((d) => p.days.includes(d)),
        startTime: p.startTime,
        minutes: Number(p.minutes)
      }))
    };
  }

  async runPreview() {
    this.isBusy = true;
    this.errorMessage = undefined;
    this.preview = undefined;
    try {
      this.preview = await previewClass({ request: this.request });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleRefreshPreview() {
    this.runPreview();
  }

  get firstSessions() {
    return (this.preview?.firstSessions || []).map((value, i) => ({
      key: `s${i}`,
      value
    }));
  }
  get hasWarnings() {
    return Boolean(this.preview?.warnings?.length);
  }
  get warnings() {
    return (this.preview?.warnings || []).map((text, i) => ({
      key: `w${i}`,
      text
    }));
  }
  get clashCount() {
    return this.preview?.clashes?.length || 0;
  }
  get hasClashes() {
    return this.clashCount > 0;
  }
  get clashes() {
    return (this.preview?.clashes || [])
      .slice(0, MAX_CLASHES)
      .map((text, i) => ({ key: `c${i}`, text }));
  }
  get moreClashes() {
    return Math.max(0, this.clashCount - MAX_CLASHES);
  }
  get clashTileClass() {
    return this.hasClashes ? "stat stat_bad" : "stat stat_good";
  }
  get noSessions() {
    return this.preview && !this.preview.sessions;
  }
  get createLabel() {
    return this.hasClashes
      ? "Create without the clashing sessions"
      : "Create class";
  }

  async handleCreate() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await createClass({ request: this.request });
      this.close({ classId: result.classId, sessions: result.sessions });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
