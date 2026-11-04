import { LightningElement, api } from "lwc";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getDetails from "@salesforce/apex/ClassSetupController.getDetails";
import saveClass from "@salesforce/apex/ClassSetupController.saveClass";
import { reduceErrors, toast } from "c/kemUtils";

const MODES = ["Classroom", "Online", "Hybrid"].map((v) => ({
  label: v,
  value: v
}));
const NONE = "";
const MAX_CLASHES = 6;

/**
 * Class set-up: who teaches the class (login and faculty), where (branch and
 * room), seats, delivery and status. On the class page it shows the set-up
 * and what is missing; Edit (or the Set-up Centre) opens the form. A new
 * teacher or room reaches the upcoming sessions; clashes are listed.
 * In a modal (inModal) it opens in edit mode and fires "saved" / "cancel".
 */
export default class KemClassSetup extends LightningElement {
  @api recordId;
  @api inModal = false;
  modeOptions = MODES;
  details;
  form;
  editing = false;
  result;
  errorMessage;
  hidden = false;
  isBusy = false;
  isLoading = true;

  connectedCallback() {
    this.editing = this.inModal;
    this.load();
  }

  async load(branchId) {
    this.isLoading = true;
    try {
      this.details = await getDetails({
        classId: this.recordId,
        branchId: branchId || null
      });
      if (!branchId) {
        const d = this.details;
        this.form = {
          branchId: d.branchId || NONE,
          roomId: d.roomId || NONE,
          teacherUserId: d.teacherUserId || NONE,
          facultyId: d.facultyId || NONE,
          capacity: d.capacity,
          deliveryMode: d.deliveryMode || "Classroom",
          status: d.status
        };
      }
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = !this.inModal && message.includes("do not have access");
      this.errorMessage = message;
    } finally {
      this.isLoading = false;
    }
  }

  get visible() {
    return !this.hidden;
  }

  // ------------------------------------------------------------ view

  label(options, value, empty) {
    const o = (options || []).find((x) => x.value === value);
    return o ? o.label : empty;
  }
  get teacherName() {
    const d = this.details;
    return this.label(
      [...(d?.teachers || []), ...(d?.otherStaff || [])],
      d?.teacherUserId,
      "Not assigned"
    );
  }
  get facultyName() {
    return this.label(
      this.details?.faculty,
      this.details?.facultyId,
      "Not assigned"
    );
  }
  get roomName() {
    return this.label(
      this.details?.rooms,
      this.details?.roomId,
      this.details?.deliveryMode === "Online"
        ? "Online (no room)"
        : "Not assigned"
    );
  }
  get branchName() {
    return this.label(
      this.details?.branches,
      this.details?.branchId,
      "Not assigned"
    );
  }
  get seatsText() {
    const d = this.details;
    return d?.capacity
      ? `${d.seatsTaken} of ${d.capacity} taken`
      : "No seat limit";
  }
  get problems() {
    const d = this.details;
    if (!d) {
      return [];
    }
    const list = [];
    if (!d.branchId)
      list.push("No branch: prices, invoices and branch desks need one.");
    if (!d.teacherUserId)
      list.push(
        "No teacher login: registers, marks, cover and My sessions need one."
      );
    if (!d.facultyId)
      list.push(
        "No faculty shown to families on the timetable and report cards."
      );
    if (!d.roomId && d.deliveryMode !== "Online")
      list.push("No room: room clashes and seating cannot be checked.");
    if (!d.capacity)
      list.push(
        "No seat limit: the class can never be full or have a waitlist."
      );
    if (d.teacherUserId && d.upcomingWithoutTeacher) {
      list.push(
        `${d.upcomingWithoutTeacher} upcoming sessions have no teacher (clashes or cover); check the timetable.`
      );
    }
    if (!d.patterns)
      list.push(
        "No weekly times yet: use the class menu above → Add weekly pattern, then Generate sessions."
      );
    else if (
      !d.upcomingSessions &&
      d.status !== "Completed" &&
      d.status !== "Cancelled"
    ) {
      list.push(
        "No upcoming sessions: use the class menu above → Generate sessions."
      );
    }
    return list.map((text, i) => ({ key: `p${i}`, text }));
  }
  get hasProblems() {
    return this.problems.length > 0;
  }

  get showEditButton() {
    return Boolean(this.details?.canEdit) && !this.editing;
  }

  handleEdit() {
    this.result = undefined;
    this.editing = true;
  }

  // ------------------------------------------------------------ form

  get branchOptions() {
    return [
      { label: "Choose a branch", value: NONE },
      ...(this.details?.branches || [])
    ];
  }
  get roomOptions() {
    return [
      { label: "No room", value: NONE },
      ...(this.details?.rooms || []).map((r) => ({
        label: r.label,
        value: r.value
      }))
    ];
  }
  get teacherOptions() {
    const d = this.details || {};
    return [
      { label: "No teacher", value: NONE },
      ...(d.teachers || []).map((t) => ({ label: t.label, value: t.value })),
      ...(d.otherStaff || []).map((t) => ({
        label: `${t.label} (${t.detail})`,
        value: t.value
      }))
    ];
  }
  get facultyOptions() {
    return [
      { label: "None", value: NONE },
      ...(this.details?.faculty || []).map((f) => ({
        label: f.detail
          ? `${f.label} (${f.detail.replace(/^Faculty – /, "")})`
          : f.label,
        value: f.value
      }))
    ];
  }
  get statusOptions() {
    return this.details?.statuses || [];
  }
  get noTeachers() {
    return !(this.details?.teachers || []).length;
  }
  get selectedRoomSeats() {
    const r = (this.details?.rooms || []).find(
      (x) => x.value === this.form?.roomId
    );
    return r?.detail ? Math.round(Number(r.detail)) : null;
  }
  get roomTooSmall() {
    return (
      this.selectedRoomSeats !== null &&
      Number(this.form.capacity) > this.selectedRoomSeats
    );
  }
  get teacherChanged() {
    return (
      (this.form?.teacherUserId || null) !==
      (this.details?.teacherUserId || null)
    );
  }
  get roomChanged() {
    return (this.form?.roomId || null) !== (this.details?.roomId || null);
  }
  get showSessionNote() {
    return (
      (this.teacherChanged || this.roomChanged) &&
      this.details?.upcomingSessions > 0
    );
  }
  get cannotSave() {
    return (
      this.isBusy ||
      !this.form?.branchId ||
      !(Number(this.form?.capacity) >= 1) ||
      this.roomTooSmall
    );
  }

  async handleField(event) {
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.form = { ...this.form, [field]: value };
    if (field === "branchId" && value) {
      this.form = { ...this.form, roomId: NONE };
      await this.load(value);
    }
  }

  handleCancel() {
    if (this.inModal) {
      this.dispatchEvent(new CustomEvent("cancel"));
      return;
    }
    this.editing = false;
    this.load();
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    const f = this.form;
    try {
      const result = await saveClass({
        request: {
          classId: this.recordId,
          branchId: f.branchId || null,
          roomId: f.roomId || null,
          teacherUserId: f.teacherUserId || null,
          facultyId: f.facultyId || null,
          capacity: Number(f.capacity),
          deliveryMode: f.deliveryMode,
          status: f.status
        }
      });
      const clashes = result.clashes || [];
      this.result = {
        updated: result.updated,
        clashes: clashes
          .slice(0, MAX_CLASHES)
          .map((text, i) => ({ key: `c${i}`, text })),
        more: Math.max(0, clashes.length - MAX_CLASHES),
        hasClashes: clashes.length > 0
      };
      notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
      const message = result.updated
        ? `Saved; ${result.updated} upcoming session${result.updated === 1 ? "" : "s"} updated.`
        : "Saved.";
      if (this.inModal && !clashes.length) {
        this.dispatchEvent(
          new CustomEvent("saved", { detail: { ...result, message } })
        );
        return;
      }
      toast(
        this,
        "Class saved",
        message,
        clashes.length ? "warning" : "success"
      );
      this.editing = false;
      await this.load();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  handleDone() {
    this.dispatchEvent(
      new CustomEvent("saved", {
        detail: { updated: this.result?.updated || 0 }
      })
    );
  }

  get showDone() {
    return this.inModal && this.result && !this.editing;
  }
}
