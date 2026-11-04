import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import LightningConfirm from "lightning/confirm";
import getWeek from "@salesforce/apex/TimetableController.getWeek";
import getFilters from "@salesforce/apex/TimetableController.getFilters";
import previewMove from "@salesforce/apex/TimetableController.previewMove";
import reschedule from "@salesforce/apex/TimetableController.reschedule";
import cancelSession from "@salesforce/apex/TimetableController.cancelSession";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const FIRST_HOUR = 7;
const LAST_HOUR = 21;
const HOUR_PX = 56;
const SNAP_MINUTES = 15;
const PALETTE = 8;

function startOfWeek(date) {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const offset = (d.getDay() + 6) % 7; // Monday first
  d.setDate(d.getDate() - offset);
  return d;
}

function isoDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function timeLabel(date) {
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function hashIndex(value) {
  let hash = 0;
  for (const ch of value || "") {
    hash = (hash * 33 + ch.charCodeAt(0)) % 9973;
  }
  return hash % PALETTE;
}

export default class KemTimetable extends NavigationMixin(LightningElement) {
  weekStart = startOfWeek(new Date());
  branchId = "";
  teacherId = "";
  roomId = "";
  filters;
  sessions = [];
  errorMessage;
  selectedId;
  selectedDayKey = isoDate(new Date());
  dragId;
  dragOffsetMinutes = 0;
  dropKey;
  wiredWeek;
  now = new Date();

  @wire(getFilters)
  wiredFilters({ data, error }) {
    if (data) {
      this.filters = data;
    } else if (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  @wire(getWeek, {
    weekStart: "$weekParam",
    branchId: "$branchParam",
    teacherId: "$teacherParam",
    roomId: "$roomParam"
  })
  wiredSessions(result) {
    this.wiredWeek = result;
    if (result.data) {
      this.sessions = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get weekParam() {
    return isoDate(this.weekStart);
  }
  get branchParam() {
    return this.branchId || null;
  }
  get teacherParam() {
    return this.teacherId || null;
  }
  get roomParam() {
    return this.roomId || null;
  }

  get branchOptions() {
    return [
      { label: "All branches", value: "" },
      ...(this.filters?.branches || [])
    ];
  }
  get teacherOptions() {
    const mine = this.filters
      ? [{ label: "My sessions", value: this.filters.currentUserId }]
      : [];
    return [
      { label: "All teachers", value: "" },
      ...mine,
      ...(this.filters?.teachers || []).filter(
        (t) => t.value !== this.filters.currentUserId
      )
    ];
  }
  get roomOptions() {
    return [{ label: "All rooms", value: "" }, ...(this.filters?.rooms || [])];
  }

  get weekLabel() {
    const end = new Date(this.weekStart);
    end.setDate(end.getDate() + 6);
    const fmt = new Intl.DateTimeFormat(undefined, {
      day: "numeric",
      month: "short"
    });
    return `${fmt.format(this.weekStart)} – ${fmt.format(end)} ${end.getFullYear()}`;
  }
  get sessionCount() {
    return this.sessions.length;
  }
  get gridStyle() {
    return `--hour-px: ${HOUR_PX}px; --hours: ${LAST_HOUR - FIRST_HOUR};`;
  }
  get hours() {
    const list = [];
    for (let h = FIRST_HOUR; h < LAST_HOUR; h++) {
      list.push({
        label: `${String(h).padStart(2, "0")}:00`,
        style: `top: ${(h - FIRST_HOUR) * HOUR_PX}px`
      });
    }
    return list;
  }
  get nowStyle() {
    const minutes =
      this.now.getHours() * 60 + this.now.getMinutes() - FIRST_HOUR * 60;
    return `top: ${(minutes / 60) * HOUR_PX}px`;
  }

  get days() {
    const todayKey = isoDate(new Date());
    const dowFmt = new Intl.DateTimeFormat(undefined, { weekday: "short" });
    const list = [];
    for (let i = 0; i < 7; i++) {
      const date = new Date(this.weekStart);
      date.setDate(date.getDate() + i);
      const key = isoDate(date);
      const isToday = key === todayKey;
      const isSelected = key === this.selectedDayKey;
      const sessions = this.sessions
        .filter((s) => isoDate(new Date(s.startAt)) === key)
        .map((s) => this.decorate(s));
      list.push({
        key,
        dow: dowFmt.format(date),
        dom: date.getDate(),
        isToday,
        sessions,
        selectedAttr: isSelected ? "true" : "false",
        headClass: `day-head${isToday ? " day-head_today" : ""}${isSelected ? " day_selected" : ""}`,
        columnClass: `day-col${this.dropKey === key ? " day-col_drop" : ""}${isSelected ? " day_selected" : ""}`,
        pillClass: `day-pill${isSelected ? " day-pill_selected" : ""}${isToday ? " day-pill_today" : ""}`
      });
    }
    return list;
  }

  get selected() {
    const s = this.sessions.find((x) => x.id === this.selectedId);
    if (!s) {
      return null;
    }
    const d = this.decorate(s);
    return {
      ...d,
      dayLabel: new Intl.DateTimeFormat(undefined, {
        weekday: "long",
        day: "numeric",
        month: "long"
      }).format(new Date(s.startAt)),
      statusClass:
        s.status === "Cancelled"
          ? "kem-badge kem-badge_danger"
          : s.status === "Completed"
            ? "kem-badge kem-badge_success"
            : "kem-badge kem-badge_info",
      isScheduled: s.status === "Scheduled"
    };
  }

  decorate(s) {
    const start = new Date(s.startAt);
    const end = new Date(s.endAt);
    const startMinutes =
      start.getHours() * 60 + start.getMinutes() - FIRST_HOUR * 60;
    const duration = Math.max(15, (end - start) / 60000);
    const top = Math.max(0, (startMinutes / 60) * HOUR_PX);
    const height = Math.max(22, (duration / 60) * HOUR_PX - 2);
    const cancelled = s.status === "Cancelled";
    return {
      ...s,
      className_: s.className || s.name,
      timeLabel: `${timeLabel(start)} – ${timeLabel(end)}`,
      roomName: s.roomName || "No room",
      teacherName: s.teacherName || "Unassigned",
      courseName: s.courseName || "—",
      draggable: cancelled ? "false" : "true",
      ariaLabel: `${s.className || s.name}, ${timeLabel(start)} to ${timeLabel(end)}, ${s.status}`,
      style: `top: ${top}px; height: ${height}px;`,
      className: `session session_c${hashIndex(s.classId)}${cancelled ? " session_cancelled" : ""}${s.id === this.selectedId ? " session_selected" : ""}`
    };
  }

  // ------------------------------------------------------------ navigation

  shiftWeek(days) {
    const next = new Date(this.weekStart);
    next.setDate(next.getDate() + days);
    this.weekStart = next;
    this.selectedId = undefined;
  }
  handlePrev() {
    this.shiftWeek(-7);
  }
  handleNext() {
    this.shiftWeek(7);
  }
  handleToday() {
    this.weekStart = startOfWeek(new Date());
    this.selectedDayKey = isoDate(new Date());
    this.now = new Date();
  }
  handleBranch(event) {
    this.branchId = event.detail.value;
  }
  handleTeacher(event) {
    this.teacherId = event.detail.value;
  }
  handleRoom(event) {
    this.roomId = event.detail.value;
  }
  handlePickDay(event) {
    this.selectedDayKey = event.currentTarget.dataset.key;
  }

  handleSelect(event) {
    this.selectedId = event.currentTarget.dataset.id;
  }
  handleKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.selectedId = event.currentTarget.dataset.id;
    }
  }
  handleCloseDrawer() {
    this.selectedId = undefined;
  }
  handleOpenClass(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  // --------------------------------------------------------- drag and drop

  handleDragStart(event) {
    this.dragId = event.currentTarget.dataset.id;
    const rect = event.currentTarget.getBoundingClientRect();
    this.dragOffsetMinutes = ((event.clientY - rect.top) / HOUR_PX) * 60;
    event.dataTransfer.setData("text/plain", this.dragId);
    event.dataTransfer.effectAllowed = "move";
  }

  handleDragOver(event) {
    event.preventDefault();
    this.dropKey = event.currentTarget.dataset.key;
  }

  handleDragLeave() {
    this.dropKey = undefined;
  }

  async handleDrop(event) {
    event.preventDefault();
    const key = event.currentTarget.dataset.key;
    this.dropKey = undefined;
    const session = this.sessions.find(
      (s) => s.id === (event.dataTransfer.getData("text/plain") || this.dragId)
    );
    if (!session) {
      return;
    }
    const rect = event.currentTarget.getBoundingClientRect();
    const rawMinutes =
      ((event.clientY - rect.top) / HOUR_PX) * 60 -
      this.dragOffsetMinutes +
      FIRST_HOUR * 60;
    const snapped = Math.max(
      FIRST_HOUR * 60,
      Math.round(rawMinutes / SNAP_MINUTES) * SNAP_MINUTES
    );
    const [y, m, d] = key.split("-").map(Number);
    const newStart = new Date(
      y,
      m - 1,
      d,
      Math.floor(snapped / 60),
      snapped % 60
    );
    const duration = new Date(session.endAt) - new Date(session.startAt);
    const newEnd = new Date(newStart.getTime() + duration);
    if (newStart.getTime() === new Date(session.startAt).getTime()) {
      return;
    }
    await this.move(session, newStart, newEnd);
  }

  async move(session, newStart, newEnd) {
    try {
      const preview = await previewMove({
        sessionId: session.id,
        newStart: newStart.toISOString(),
        newEnd: newEnd.toISOString(),
        newRoomId: null
      });
      if (preview.blocked) {
        toast(
          this,
          "Cannot move session",
          preview.conflicts
            .filter((c) => c.blocking)
            .map((c) => c.message)
            .join(" "),
          "error"
        );
        return;
      }
      const warnings = preview.conflicts
        .filter((c) => !c.blocking)
        .map((c) => c.message);
      const confirmed = await LightningConfirm.open({
        label: "Reschedule session",
        theme: warnings.length ? "warning" : "default",
        message: `Move to ${newStart.toLocaleString()}?${warnings.length ? " " + warnings.join(" ") : ""}`
      });
      if (!confirmed) {
        return;
      }
      await reschedule({
        sessionId: session.id,
        newStart: newStart.toISOString(),
        newEnd: newEnd.toISOString(),
        newRoomId: null,
        reason: "Rescheduled on the timetable"
      });
      toast(
        this,
        "Session rescheduled",
        `${session.className || session.name} moved.`
      );
      await refreshApex(this.wiredWeek);
    } catch (error) {
      toastError(this, error, "Session could not be moved");
    }
  }

  async handleCancelSession() {
    const reason = await ReasonModal.open({
      size: "small",
      label: "Cancel session",
      message: "The session stays on the timetable as cancelled for history.",
      confirmLabel: "Cancel session",
      confirmVariant: "destructive"
    });
    if (!reason) {
      return;
    }
    try {
      await cancelSession({ sessionId: this.selectedId, reason });
      toast(this, "Session cancelled", "The session was cancelled.");
      await refreshApex(this.wiredWeek);
    } catch (error) {
      toastError(this, error, "Session could not be cancelled");
    }
  }
}
