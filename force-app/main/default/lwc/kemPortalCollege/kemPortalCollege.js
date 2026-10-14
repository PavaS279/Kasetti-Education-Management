import { LightningElement, api } from "lwc";

const money = (value) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(value || 0);

function time(value) {
  if (!value) {
    return "";
  }
  return new Date(value).toLocaleTimeString("en-IN", {
    hour: "2-digit",
    minute: "2-digit"
  });
}

function dash(value) {
  return value === null || value === undefined ? "—" : String(value);
}

/** Student-first college card in the portal: programme, roll number, today, subjects and term results. */
export default class KemPortalCollege extends LightningElement {
  @api summary;

  get rollLabel() {
    return this.summary?.rollNumber
      ? `Roll number ${this.summary.rollNumber}`
      : "Roll number after the fee is received";
  }

  get feesDue() {
    return money(this.summary?.feesDue);
  }

  get duesClass() {
    return this.summary?.feesDue > 0 ? "fact warn" : "fact ok";
  }

  get periods() {
    return (this.summary?.today || []).map((p, i) => ({
      key: `p${i}`,
      time: `${time(p.startsAt)}–${time(p.endsAt)}`,
      subject: p.subject || "Class",
      where: [p.room, p.faculty, p.status === "Cancelled" ? "Cancelled" : null]
        .filter(Boolean)
        .join(" · ")
    }));
  }

  get hasToday() {
    return this.periods.length > 0;
  }

  get subjects() {
    return (this.summary?.subjects || []).map((s, i) => ({
      key: `s${i}`,
      name: s.attempt > 1 ? `${s.name} (attempt ${s.attempt})` : s.name,
      term: s.term,
      attendance:
        s.attendancePercent === null || s.attendancePercent === undefined
          ? "—"
          : `${s.attendancePercent}%`,
      internal: s.published ? dash(s.internalMarks) : "—",
      exam: s.published ? dash(s.examMarks) : "—",
      total: s.published ? `${dash(s.total)} / ${dash(s.max)}` : "—",
      result: s.published ? s.result : "Result awaited"
    }));
  }

  get hasSubjects() {
    return this.subjects.length > 0;
  }

  get terms() {
    return (this.summary?.terms || []).map((t) => ({
      key: `t${t.term}`,
      label: `Term ${t.term}: ${t.outcome} · ${t.percentage}% · backlogs ${t.backlogs}`
    }));
  }

  get hasTerms() {
    return this.terms.length > 0;
  }
}
