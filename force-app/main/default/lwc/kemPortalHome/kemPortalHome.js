import { LightningElement } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import getHome from "@salesforce/apex/PortalController.getHome";
import getLearner from "@salesforce/apex/PortalController.getLearner";
import markMessageRead from "@salesforce/apex/PortalController.markMessageRead";
import downloadDocument from "@salesforce/apex/PortalController.downloadDocument";
import startPayment from "@salesforce/apex/PortalController.startPayment";
import { reduceErrors, initials, toneFor } from "c/kemUtils";

const VIEWS = [
  { value: "timetable", label: "Timetable", icon: "utility:event" },
  { value: "results", label: "Results", icon: "utility:trophy" },
  { value: "attendance", label: "Attendance", icon: "utility:check" },
  { value: "fees", label: "Fees", icon: "utility:moneybag" },
  { value: "documents", label: "Documents", icon: "utility:file" },
  { value: "library", label: "Library", icon: "utility:knowledge_base" },
  { value: "transport", label: "Transport", icon: "utility:travel_and_places" }
];

const DOC_ICON = {
  Invoice: "doctype:pdf",
  Receipt: "doctype:pdf",
  "Report Card": "doctype:pdf",
  "Offer Letter": "doctype:pdf"
};

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
  showInbox = false;
  openMessageId;
  downloadingId;
  payingId;
  paymentNotice;

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
  get showLibrary() {
    return this.view === "library";
  }
  get loans() {
    return (this.detail?.loans || []).map((l) => ({
      ...l,
      dueLabel:
        l.status === "Returned" || l.status === "Lost"
          ? `${l.status} ${formatDate(l.returnedOn)}`
          : `Due ${formatDate(l.dueOn)}`,
      className: `loan${l.daysOverdue > 0 ? " loan_overdue" : ""}`,
      overdueLabel: l.daysOverdue > 0 ? `${l.daysOverdue} day(s) overdue` : "",
      hasFine: l.fineStatus === "Due"
    }));
  }
  get noLoans() {
    return this.loans.length === 0;
  }
  get showTransport() {
    return this.view === "transport";
  }
  get transport() {
    return (this.detail?.transport || []).map((t, i) => ({
      ...t,
      key: String(i),
      times: [
        t.pickupTime ? `Pick-up ${t.pickupTime}` : null,
        t.dropTime ? `Drop ${t.dropTime}` : null
      ]
        .filter((x) => x)
        .join(" · "),
      driverLine: [t.driver, t.driverPhone].filter((x) => x).join(" · "),
      since: `Since ${formatDate(t.startDate)}`
    }));
  }
  get noTransport() {
    return this.transport.length === 0;
  }
  get showDocuments() {
    return this.view === "documents";
  }

  // ------------------------------------------------------------ inbox
  get unread() {
    return this.home?.unreadMessages || 0;
  }
  get inboxLabel() {
    return this.unread ? `Messages (${this.unread} new)` : "Messages";
  }
  get messages() {
    return (this.home?.messages || []).map((m) => ({
      ...m,
      when: `${formatDay(m.sentOn)} · ${formatTime(m.sentOn)}`,
      className: `message${m.read ? "" : " message_unread"}`,
      open: m.id === this.openMessageId,
      expanded: m.id === this.openMessageId ? "true" : "false"
    }));
  }
  get noMessages() {
    return this.messages.length === 0;
  }

  // -------------------------------------------------- grades, documents
  get grades() {
    return (this.detail?.grades || []).map((g) => {
      const grade = g.grade || "—";
      return {
        ...g,
        gradeLabel: grade,
        gradeClass: `grade grade_${grade.replace("+", "plus").toLowerCase()}`,
        scoreLabel: g.score == null ? "" : `${Number(g.score).toFixed(1)}%`,
        isFinal: g.status === "Final",
        statusLabel: g.status === "Final" ? "Final" : "Provisional — may change"
      };
    });
  }
  get hasGrades() {
    return this.grades.length > 0;
  }
  get documents() {
    return (this.detail?.documents || []).map((d) => ({
      ...d,
      icon: DOC_ICON[d.kind] || "doctype:attachment",
      dateLabel: formatDate(d.createdDate),
      busy: d.versionId === this.downloadingId,
      downloadLabel: `Download ${d.title}`
    }));
  }
  get noDocuments() {
    return this.documents.length === 0;
  }
  get waitlist() {
    return (this.detail?.waitlist || []).map((w) => ({
      ...w,
      offered: w.status === "Offered",
      text:
        w.status === "Offered"
          ? `A seat is held for you until ${formatDay(w.offerExpires)} ${formatTime(w.offerExpires)}. Please contact us to confirm.`
          : `Number ${w.position} on the waiting list.`,
      className: `wait${w.status === "Offered" ? " wait_offer" : ""}`
    }));
  }
  get hasWaitlist() {
    return this.waitlist.length > 0;
  }
  get creditBalance() {
    return this.detail?.creditBalance || 0;
  }
  get hasCredit() {
    return this.creditBalance > 0;
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
      className: `invoice${i.overdue ? " invoice_overdue" : ""}`,
      period: i.billingPeriod ? ` · ${i.billingPeriod}` : "",
      canPay:
        this.detail?.payOnline === true &&
        i.balance > 0 &&
        (i.status === "Issued" || i.status === "Partially Paid"),
      hasPlan: (i.instalments || []).length > 0,
      plan: (i.instalments || []).map((p) => ({
        ...p,
        key: `${i.id}-${p.sequence}`,
        dueLabel: formatDate(p.dueDate),
        className: `step${p.status === "Paid" ? " step_paid" : ""}${p.overdue ? " step_overdue" : ""}`,
        statusLabel: p.overdue ? "Overdue" : p.status
      }))
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

  handleInbox() {
    this.showInbox = !this.showInbox;
  }

  async handleOpenMessage(event) {
    const id = event.currentTarget.dataset.id;
    this.openMessageId = this.openMessageId === id ? undefined : id;
    const message = this.home.messages.find((m) => m.id === id);
    if (message && !message.read) {
      try {
        await markMessageRead({ messageId: id });
        this.home = {
          ...this.home,
          unreadMessages: Math.max(0, this.home.unreadMessages - 1),
          messages: this.home.messages.map((m) => {
            return m.id === id ? { ...m, read: true } : m;
          })
        };
      } catch {
        // Reading still works; the unread marker stays until the next visit.
      }
    }
  }

  async handlePay(event) {
    const invoiceId = event.currentTarget.dataset.id;
    this.paymentNotice = undefined;
    this.payingId = invoiceId;
    try {
      const link = await startPayment({ invoiceId });
      if (link.mode === "Live" && link.checkoutUrl) {
        window.open(link.checkoutUrl, "_blank", "noopener");
        this.paymentNotice = `Complete the payment of ${link.invoiceNumber} in the payment window. Your receipt appears here once the payment is confirmed.`;
      } else {
        this.paymentNotice = `Test mode: payment request ${link.linkNumber} for ${link.invoiceNumber} was created. No money is taken.`;
      }
    } catch (error) {
      this.paymentNotice = reduceErrors(error).join(" ");
    } finally {
      this.payingId = undefined;
    }
  }

  async handleDownload(event) {
    const versionId = event.currentTarget.dataset.id;
    this.downloadingId = versionId;
    try {
      const file = await downloadDocument({ versionId });
      const link = document.createElement("a");
      link.href = `data:application/pdf;base64,${file.base64}`;
      link.download = file.fileName;
      link.click();
    } catch (error) {
      this.detailError = reduceErrors(error).join(" ");
    } finally {
      this.downloadingId = undefined;
    }
  }
}
