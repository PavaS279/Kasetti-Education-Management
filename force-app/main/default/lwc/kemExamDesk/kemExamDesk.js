import { LightningElement, api, wire } from "lwc";
import LightningPrompt from "lightning/prompt";
import getExams from "@salesforce/apex/ExamController.getExams";
import getExam from "@salesforce/apex/ExamController.getExam";
import registerCandidates from "@salesforce/apex/ExamController.registerCandidates";
import checkEligibility from "@salesforce/apex/ExamController.checkEligibility";
import overrideCandidate from "@salesforce/apex/ExamController.overrideCandidate";
import allocateSeats from "@salesforce/apex/ExamController.allocateSeats";
import issueTickets from "@salesforce/apex/ExamController.issueTickets";
import getMarkSheet from "@salesforce/apex/ExamController.getMarkSheet";
import saveMarks from "@salesforce/apex/ExamController.saveMarks";
import publishMarks from "@salesforce/apex/ExamController.publishMarks";
import canSetUpExams from "@salesforce/apex/ExamController.canSetUpExams";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const STATUS_BADGE = {
  Eligible: "kem-badge kem-badge_success",
  "Ticket Issued": "kem-badge kem-badge_info",
  Withheld: "kem-badge kem-badge_danger",
  Registered: "kem-badge"
};

function formatDate(value) {
  if (!value) {
    return "";
  }
  const [y, m, d] = String(value).split("-");
  return `${d}/${m}/${y}`;
}

/** Exam desk: candidates, eligibility, seating, hall tickets and marks. */
export default class KemExamDesk extends LightningElement {
  @api recordId;
  exams;
  detail;
  selectedExamId;
  errorMessage;
  hidden = false;
  isBusy = false;
  selectedRooms = [];
  sheet;
  marks = [];
  canSetUp = false;
  showNewExam = false;
  showNewPaper = false;

  @wire(canSetUpExams)
  wiredSetUp({ data }) {
    this.canSetUp = data === true;
  }

  connectedCallback() {
    this.loadExams();
  }

  async loadExams() {
    try {
      this.exams = await getExams({ branchId: this.recordId || null });
      this.errorMessage = undefined;
      if (!this.selectedExamId && this.exams.length) {
        await this.selectExam(this.exams[0].examId);
      }
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  async selectExam(examId) {
    this.selectedExamId = examId;
    this.sheet = undefined;
    try {
      this.detail = await getExam({ examId });
      if (!this.selectedRooms.length) {
        this.selectedRooms = (this.detail.rooms || []).map((r) => r.roomId);
      }
    } catch (error) {
      toastError(this, error);
    }
  }

  // ---------------------------------------------------------------- view

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.exams && !this.errorMessage;
  }
  get hasExams() {
    return (this.exams || []).length > 0;
  }
  get examOptions() {
    return (this.exams || []).map((e) => ({
      label: `${e.name} (${e.code}) · ${e.status}`,
      value: e.examId
    }));
  }
  get exam() {
    return this.detail?.exam;
  }
  get dates() {
    return [formatDate(this.exam?.startDate), formatDate(this.exam?.endDate)]
      .filter((x) => x)
      .join(" – ");
  }
  get canManage() {
    return this.detail?.canManage === true;
  }
  get tiles() {
    const c = this.detail?.counts || {};
    return [
      {
        key: "papers",
        label: "Papers",
        value: (this.detail?.papers || []).length
      },
      { key: "reg", label: "Registered", value: c.Registered || 0 },
      { key: "ok", label: "Eligible", value: c.Eligible || 0 },
      {
        key: "held",
        label: "Withheld",
        value: c.Withheld || 0,
        warn: (c.Withheld || 0) > 0
      },
      { key: "issued", label: "Tickets issued", value: c["Ticket Issued"] || 0 }
    ].map((t) => ({ ...t, className: `tile${t.warn ? " tile_warn" : ""}` }));
  }
  get papers() {
    return (this.detail?.papers || []).map((p) => ({
      ...p,
      when: `${formatDate(p.paperDate)} ${p.startTime || ""}`.trim(),
      marksLabel: p.marksStatus === "Published" ? "View marks" : "Enter marks"
    }));
  }
  get candidates() {
    const canOverride = this.detail?.canOverride === true;
    return (this.detail?.candidates || []).map((c) => ({
      ...c,
      badge: STATUS_BADGE[c.status] || "kem-badge",
      seatLabel: c.seat || "—",
      note: c.overrideReason ? `Allowed: ${c.overrideReason}` : c.reason || "",
      canOverride: canOverride && c.status === "Withheld"
    }));
  }
  get hasCandidates() {
    return this.candidates.length > 0;
  }
  get roomOptions() {
    return (this.detail?.rooms || []).map((r) => ({
      label: `${r.name} (${r.capacity} seats)`,
      value: r.roomId
    }));
  }
  get markRows() {
    const editable = this.sheet?.editable === true;
    return this.marks.map((m) => ({
      ...m,
      disabled: !editable || m.absent,
      absentDisabled: !editable
    }));
  }
  get sheetTitle() {
    return this.sheet
      ? `${this.sheet.paper.name} · ${this.sheet.paper.className} · out of ${this.sheet.paper.maxMarks}`
      : "";
  }
  get publishDisabled() {
    return (
      this.isBusy ||
      !this.sheet?.editable ||
      this.sheet?.paper.marksStatus !== "Draft"
    );
  }

  // ---------------------------------------------------------------- set-up

  toggleNewExam() {
    this.showNewExam = !this.showNewExam;
  }

  toggleNewPaper() {
    this.showNewPaper = !this.showNewPaper;
  }

  async handleExamCreated(event) {
    this.showNewExam = false;
    toast(this, "Exam created", "Add one paper per class next.", "success");
    this.selectedExamId = event.detail.id;
    await this.loadExams();
    await this.selectExam(event.detail.id);
    this.showNewPaper = true;
  }

  async handlePaperCreated() {
    this.showNewPaper = false;
    toast(this, "Paper added", "", "success");
    await this.selectExam(this.selectedExamId);
  }

  // ---------------------------------------------------------------- events

  handleExam(event) {
    this.selectedRooms = [];
    this.selectExam(event.detail.value);
  }

  handleRooms(event) {
    this.selectedRooms = event.detail.value;
  }

  handleRegister() {
    this.step(
      () => registerCandidates({ examId: this.selectedExamId }),
      "Candidates registered"
    );
  }

  handleCheck() {
    this.step(
      () => checkEligibility({ examId: this.selectedExamId }),
      "Eligibility checked"
    );
  }

  handleSeats() {
    this.step(
      () =>
        allocateSeats({
          examId: this.selectedExamId,
          roomIds: this.selectedRooms
        }),
      "Seats allocated"
    );
  }

  handleIssue() {
    this.step(
      () => issueTickets({ examId: this.selectedExamId }),
      "Hall tickets issued"
    );
  }

  async handleOverride(event) {
    const candidateId = event.currentTarget.dataset.id;
    const reason = await LightningPrompt.open({
      label: "Allow this candidate",
      message: "Why is this candidate allowed to sit the exam?",
      variant: "header"
    });
    if (!reason) {
      return;
    }
    await this.run(async () => {
      await overrideCandidate({ candidateId, reason });
      toast(this, "Candidate allowed", "", "success");
    });
  }

  async step(action, title) {
    await this.run(async () => {
      const result = await action();
      const parts = [`${result.processed} done`];
      if (result.skipped) {
        parts.push(`${result.skipped} skipped`);
      }
      toast(
        this,
        title,
        [...parts, ...(result.notes || [])].join(". "),
        "success"
      );
    });
  }

  async handleOpenMarks(event) {
    const paperId = event.currentTarget.dataset.id;
    try {
      this.sheet = await getMarkSheet({ paperId });
      this.marks = this.sheet.rows.map((r) => ({
        ...r,
        absent: r.absent === true
      }));
    } catch (error) {
      toastError(this, error);
    }
  }

  handleCloseMarks() {
    this.sheet = undefined;
  }

  handleMark(event) {
    const id = event.target.dataset.id;
    const field = event.target.dataset.field;
    let value = event.target.checked;
    if (field !== "absent") {
      value = event.target.value === "" ? null : Number(event.target.value);
    }
    this.marks = this.marks.map(function update(m) {
      return m.candidateId === id ? { ...m, [field]: value } : m;
    });
  }

  async handleSaveMarks() {
    await this.run(async () => {
      await saveMarks({ paperId: this.sheet.paper.paperId, rows: this.marks });
      toast(this, "Marks saved", "", "success");
      this.sheet = await getMarkSheet({ paperId: this.sheet.paper.paperId });
    }, false);
  }

  async handlePublish() {
    await this.run(async () => {
      await publishMarks({ paperId: this.sheet.paper.paperId });
      toast(
        this,
        "Marks published",
        "They are now an exam assessment in the class gradebook.",
        "success"
      );
      this.sheet = undefined;
    });
  }

  async run(action, reload = true) {
    this.isBusy = true;
    try {
      await action();
      if (reload) {
        await this.loadExams();
        await this.selectExam(this.selectedExamId);
      }
    } catch (error) {
      toastError(this, error);
    } finally {
      this.isBusy = false;
    }
  }
}
