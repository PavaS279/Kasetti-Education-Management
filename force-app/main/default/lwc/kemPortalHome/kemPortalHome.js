import { LightningElement } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import getHome from "@salesforce/apex/PortalController.getHome";
import getLearner from "@salesforce/apex/PortalController.getLearner";
import { reduceErrors, initials, toneFor } from "c/kemUtils";

const VIEWS = [
  { value: "timetable", label: "Timetable", icon: "utility:event" },
  { value: "results", label: "Results", icon: "utility:trophy" },
  { value: "attendance", label: "Attendance", icon: "utility:check" },
  { value: "fees", label: "Fees", icon: "utility:moneybag" }
];

const ATTENDANCE_CLASS = {
  Present: "dot dot_present",
  Late: "dot dot_late",
  Absent: "dot dot_absent",
  Excused: "dot dot_excused"
};

const INVOICE_CLASS = {
  Issued: "kem-badge kem-badge_info",
  "Partially Paid": "kem-badge kem-badge_warning",
  Paid: "kem-badge kem-badge_success"
};

function dayKey(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function formatDay(value) {
  const d = new Date(value);
  const today = new Date();
  const tomorrow = new Date();
  tomorrow.setDate(today.getDate() + 1);
  if (dayKey(d) === dayKey(today)) {
    return "Today";
  }
  if (dayKey(d) === dayKey(tomorrow)) {
    return "Tomorrow";
  }
  return new Intl.DateTimeFormat(undefined, {
    weekday: "long",
    day: "numeric",
    month: "short"
  }).format(d);
}

function formatTime(value) {
  return new Intl.DateTimeFormat(undefined, { timeStyle: "short" }).format(
    new Date(value)
  );
}

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "—";
}

function greeting() {
  const hour = new Date().getHours();
  if (hour < 12) {
    return "Good morning";
  }
  return hour < 17 ? "Good afternoon" : "Good evening";
}

/** Learner and guardian home for the Experience Cloud portal. */
export default class KemPortalHome extends LightningElement {
  currencyCode = CURRENCY;
  home;
  detail;
  selectedId;
  view = "timetable";
  errorMessage;
  detailError;
  isLoadingDetail = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.home = await getHome();
      this.errorMessage = undefined;
      if (this.home.learners.length) {
        await this.select(this.home.learners[0].learnerContactId);
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  async select(learnerContactId) {
    this.selectedId = learnerContactId;
    this.isLoadingDetail = true;
    try {
      this.detail = await getLearner({ learnerContactId });
      this.detailError = undefined;
    } catch (error) {
      this.detail = undefined;
      this.detailError = reduceErrors(error).join(" ");
    } finally {
      this.isLoadingDetail = false;
    }
  }

  get greetingText() {
    return `${greeting()}, ${this.home.viewerName}`;
  }
  get subtitle() {
    return this.home.isGuardian
      ? "Here is how your family is doing."
      : "Here is your week at a glance.";
  }
  get hasLearners() {
    return this.home.learners.length > 0;
  }
  get showSwitcher() {
    return this.home.learners.length > 1;
  }
  get learnerChips() {
    return this.home.learners.map((l) => ({
      ...l,
      initials: initials(l.name),
      avatarClass: `kem-avatar ${toneFor(l.name)}`,
      pressed: l.learnerContactId === this.selectedId ? "true" : "false",
      className: `chip${l.learnerContactId === this.selectedId ? " chip_on" : ""}`,
      label: l.isSelf ? `${l.name} (you)` : l.name
    }));
  }
  get card() {
    return this.detail?.learner;
  }
  get summary() {
    const c = this.card;
    if (!c) {
      return [];
    }
    return [
      {
        key: "attendance",
        label: "Attendance",
        value:
          c.attendanceRate === null || c.attendanceRate === undefined
            ? "—"
            : `${Math.round(c.attendanceRate)}%`,
        className: `tile${c.attendanceRate !== undefined && c.attendanceRate < 75 ? " tile_alert" : ""}`
      },
      {
        key: "classes",
        label: "Active classes",
        value: String(c.activeClasses),
        className: "tile"
      },
      {
        key: "next",
        label: "Next class",
        value: c.nextSessionStart
          ? `${formatDay(c.nextSessionStart)} ${formatTime(c.nextSessionStart)}`
          : "—",
        hint: c.nextSessionClass,
        className: "tile"
      }
    ];
  }
  get balanceDue() {
    return this.card?.balanceDue || 0;
  }
  get balanceClass() {
    return `tile tile_money${this.card?.overdueInvoices ? " tile_alert" : ""}`;
  }
  get overdueLabel() {
    const n = this.card?.overdueInvoices || 0;
    return n ? `${n} overdue` : "All up to date";
  }

  get views() {
    return VIEWS.map((v) => ({
      ...v,
      selected: v.value === this.view ? "true" : "false",
      className: `seg${v.value === this.view ? " seg_on" : ""}`
    }));
  }
  get showTimetable() {
    return this.view === "timetable";
  }
  get showResults() {
    return this.view === "results";
  }
  get showAttendance() {
    return this.view === "attendance";
  }
  get showFees() {
    return this.view === "fees";
  }

  get days() {
    const groups = [];
    const byKey = {};
    (this.detail?.upcoming || []).forEach((s) => {
      const key = dayKey(s.startAt);
      if (!byKey[key]) {
        byKey[key] = { key, label: formatDay(s.startAt), sessions: [] };
        groups.push(byKey[key]);
      }
      const cancelled = s.status === "Cancelled";
      byKey[key].sessions.push({
        ...s,
        time: `${formatTime(s.startAt)} – ${formatTime(s.endAt)}`,
        where: s.room || s.deliveryMode || "",
        cancelled,
        className: `session${cancelled ? " session_cancelled" : ""}`,
        canJoin: !!s.meetingUrl && !cancelled
      });
    });
    return groups;
  }
  get noSessions() {
    return this.days.length === 0;
  }
  get results() {
    return (this.detail?.results || []).map((r) => {
      const grade = r.grade || "—";
      return {
        ...r,
        gradeLabel: grade,
        gradeClass: `grade grade_${grade.replace("+", "plus").toLowerCase()}`,
        scoreLabel: r.absent
          ? "Absent"
          : `${r.score} / ${r.maxScore} · ${Math.round(r.percentage)}%`,
        meta: [r.className, r.assessmentType, formatDate(r.assessmentDate)]
          .filter(Boolean)
          .join(" · ")
      };
    });
  }
  get noResults() {
    return this.results.length === 0;
  }
  get attendance() {
    return (this.detail?.attendance || []).map((a) => ({
      ...a,
      dotClass: ATTENDANCE_CLASS[a.status] || "dot",
      when: `${formatDay(a.sessionStart)} · ${formatTime(a.sessionStart)}`,
      statusLabel:
        a.status === "Late" && a.minutesLate
          ? `Late (${a.minutesLate} min)`
          : a.status
    }));
  }
  get noAttendance() {
    return this.attendance.length === 0;
  }
  get invoices() {
    return (this.detail?.invoices || []).map((i) => ({
      ...i,
      statusClass: INVOICE_CLASS[i.status] || "kem-badge",
      dueLabel: `Due ${formatDate(i.dueDate)}`,
      className: `invoice${i.overdue ? " invoice_overdue" : ""}`
    }));
  }
  get noInvoices() {
    return this.invoices.length === 0;
  }

  handleSelect(event) {
    this.select(event.currentTarget.dataset.id);
  }
  handleView(event) {
    this.view = event.currentTarget.dataset.value;
  }
}
