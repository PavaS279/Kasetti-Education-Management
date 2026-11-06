import { LightningElement } from "lwc";
import getSetup from "@salesforce/apex/CollegeSetupController.getSetup";
import saveIntake from "@salesforce/apex/CollegeSetupController.saveIntake";
import saveRule from "@salesforce/apex/CollegeSetupController.saveRule";
import saveQuota from "@salesforce/apex/CollegeSetupController.saveQuota";
import saveSplit from "@salesforce/apex/CollegeSetupController.saveSplit";
import getFees from "@salesforce/apex/CollegeSetupController.getFees";
import saveFees from "@salesforce/apex/CollegeSetupController.saveFees";
import saveCampusCodes from "@salesforce/apex/CollegeSetupController.saveCampusCodes";
import saveBranchCode from "@salesforce/apex/CollegeSetupController.saveBranchCode";
import uploadUsns from "@salesforce/apex/CollegeSetupController.uploadUsns";
import { reduceErrors, toast } from "c/kemUtils";

/** Lateral seats for a percentage of the regular seats (nearest seat). */
export function seatsFor(regular, percentage) {
  if (
    regular === "" ||
    percentage === "" ||
    regular == null ||
    percentage == null
  ) {
    return 0;
  }
  return Math.round((Number(regular) * Number(percentage)) / 100);
}

/** The percentage a number of lateral seats is of the regular seats (2 decimals). */
export function percentOf(regular, lateral) {
  if (!Number(regular) || lateral === "" || lateral == null) {
    return null;
  }
  return Math.round((Number(lateral) * 10000) / Number(regular)) / 100;
}

/** "2026-27" -> "2025-26". */
export function previousYear(academicYear) {
  const start = Number(String(academicYear).slice(0, 4)) - 1;
  return `${start}-${String(start + 1).slice(2)}`;
}

function nextYear(academicYear) {
  const start = Number(String(academicYear).slice(0, 4)) + 1;
  return `${start}-${String(start + 1).slice(2)}`;
}

const TABS = [
  { label: "Seats & admissions", value: "intake" },
  { label: "Quotas", value: "quotas" },
  { label: "Fees", value: "fees" },
  { label: "University (VTU)", value: "vtu" },
  { label: "Eligibility rules", value: "rules" },
  { label: "Change history", value: "history" }
];

/** College Admission Setup: System Administrators edit, college staff view. */
export default class KemCollegeSetup extends LightningElement {
  setup;
  errorMessage;
  activeTab = "intake";
  editingId;
  draft = {};
  isSaving = false;
  fees;
  feeCourse;
  feeYear;
  feeStudyYear = "";
  feeEditing = false;
  feeDraft;
  feeStarts = new Date().toISOString().slice(0, 10);
  usnCsv;
  usnFileName;
  usnResult;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.setup = await getSetup();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get canEdit() {
    return Boolean(this.setup?.canEdit);
  }

  get viewOnlyNote() {
    return this.canEdit
      ? ""
      : "View only — a System Administrator changes these settings.";
  }

  get tabs() {
    return TABS.map((t) => ({
      ...t,
      className: `tab${t.value === this.activeTab ? " tab_on" : ""}`
    }));
  }

  get showIntake() {
    return this.activeTab === "intake";
  }
  get showQuotas() {
    return this.activeTab === "quotas";
  }

  get quotaRows() {
    return (this.setup?.quotas || []).map((q) => ({
      ...q,
      key: q.id,
      rankLabel: q.rankExam ? `${q.rankExam} rank needed` : "No rank needed",
      docLabel: q.extraDocument || "—",
      activeLabel: q.active ? "Active" : "Inactive",
      editing: this.editingId === q.id
    }));
  }

  get addingQuota() {
    return this.editingId === "new-quota";
  }

  get splitRows() {
    return (this.setup?.rows || []).map((r) => {
      const editing = this.editingId === `split-${r.id}`;
      const entries = editing ? this.draft.split : r.split;
      const total = (entries || []).reduce(
        (n, e) => n + Number(e.seats || 0),
        0
      );
      return {
        key: `split-${r.id}`,
        id: r.id,
        name: `${r.campus} · ${r.branch} · ${r.academicYear}`,
        intake: r.intakeRegular,
        summary: (r.split || [])
          .map(
            (e) => `${e.name} ${e.seats}${e.taken ? ` (${e.taken} taken)` : ""}`
          )
          .join(" · "),
        entries: (entries || []).map((e) => ({ ...e, key: e.quotaId })),
        totalLabel: `Total ${total} of ${r.intakeRegular} regular seats`,
        totalClass:
          total === Number(r.intakeRegular) ? "total ok" : "total bad",
        editing
      };
    });
  }

  handleAddQuota() {
    this.editingId = "new-quota";
    this.draft = {
      name: "",
      code: "",
      rankExam: "",
      extraDocument: "",
      active: true
    };
  }

  handleEditQuota(event) {
    const q = this.setup.quotas.find(
      (x) => x.id === event.currentTarget.dataset.id
    );
    this.editingId = q.id;
    this.draft = { ...q };
  }

  handleEditSplit(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.setup.rows.find((r) => r.id === id);
    this.editingId = `split-${id}`;
    this.draft = {
      campusBranchId: id,
      split: row.split.map((e) => ({ ...e }))
    };
  }

  handleSplitSeats(event) {
    const quotaId = event.target.dataset.quota;
    const seats = event.target.value === "" ? 0 : Number(event.target.value);
    this.draft = {
      ...this.draft,
      split: this.draft.split.map((e) => {
        if (e.quotaId !== quotaId) {
          return e;
        }
        return { ...e, seats };
      })
    };
  }

  async handleSaveQuota() {
    await this.save(
      () =>
        saveQuota({
          quota: {
            id: this.draft.id || null,
            name: this.draft.name,
            code: this.draft.code,
            rankExam: this.draft.rankExam,
            extraDocument: this.draft.extraDocument,
            active: this.draft.active,
            sortOrder:
              this.draft.sortOrder == null ? null : Number(this.draft.sortOrder)
          }
        }),
      "Quota saved"
    );
  }

  async handleSaveSplit() {
    await this.save(
      () =>
        saveSplit({
          campusBranchId: this.draft.campusBranchId,
          split: this.draft.split.map((e) => ({
            quotaId: e.quotaId,
            seats: Number(e.seats || 0)
          }))
        }),
      "Seats per quota saved"
    );
  }

  get showRules() {
    return this.activeTab === "rules";
  }
  get showHistory() {
    return this.activeTab === "history";
  }

  get intakeRows() {
    return (this.setup?.rows || []).map((r) => ({
      ...r,
      key: r.id,
      name: `${r.campus} · ${r.branch} · ${r.academicYear}`,
      openLabel: r.admissionsOpen ? "Open" : "Closed",
      openClass: r.admissionsOpen ? "kem-badge kem-badge_success" : "kem-badge",
      deanLabel: r.deanExceptionsAllowed ? "Allowed" : "Off",
      lateralLabel:
        r.lateralBasis === "Percentage" && r.lateralPercentage != null
          ? `${r.intakeLateral} (${r.lateralPercentage}%)`
          : `${r.intakeLateral}`,
      editing: this.editingId === r.id
    }));
  }

  get ruleRows() {
    const rows = [];
    (this.setup?.rows || []).forEach((r) => {
      [
        ["Regular", r.regularRule],
        ["Lateral", r.lateralRule]
      ].forEach(([route, rule]) => {
        if (rule && !rows.some((x) => x.ruleId === rule.ruleId)) {
          rows.push({
            key: rule.ruleId,
            ruleId: rule.ruleId,
            name: `${rule.allCampuses ? "All campuses" : r.campus} · ${r.branch} · ${r.academicYear}`,
            route,
            version: rule.version,
            level: rule.qualifyingLevel,
            minPercentage: rule.minPercentage,
            entrances: (rule.entrances || []).map((e) => ({
              ...e,
              key: e.id,
              label: e.maxRank
                ? `${e.exam} up to rank ${e.maxRank}`
                : `${e.exam} (any rank)`
            })),
            editing: this.editingId === rule.ruleId,
            editEntrances:
              this.editingId === rule.ruleId
                ? (this.draft.entrances || []).map((e) => ({
                    ...e,
                    key: e.exam,
                    label: `Highest ${e.exam} rank accepted`
                  }))
                : []
          });
        }
      });
    });
    return rows;
  }

  get historyRows() {
    return (this.setup?.history || []).map((h, i) => ({
      ...h,
      key: `${i}`,
      change: h.fromValue ? `${h.fromValue} → ${h.toValue}` : h.toValue
    }));
  }

  get isEmpty() {
    return this.setup && !this.setup.rows.length;
  }

  handleTab(event) {
    this.activeTab = event.currentTarget.dataset.value;
    this.editingId = undefined;
    if (this.activeTab === "fees" && !this.fees) {
      const first = this.setup?.rows?.[0];
      if (first) {
        this.feeCourse = first.courseId;
        this.feeYear = first.academicYear;
        this.loadFees();
      }
    }
  }

  // ------------------------------------------------------------- VTU

  get showVtu() {
    return this.activeTab === "vtu";
  }

  get vtuCampusRows() {
    return (this.setup?.vtuCampuses || []).map((c) => ({
      ...c,
      key: c.id,
      codeLabel: c.region && c.college ? `${c.region}${c.college}` : "Not set",
      editing: this.editingId === `vc-${c.id}`
    }));
  }

  get vtuBranchRows() {
    return (this.setup?.vtuBranches || []).map((b) => ({
      ...b,
      key: b.id,
      codeLabel:
        b.vtuCode ||
        (b.branchCode ? `${b.branchCode} (branch code)` : "Not set"),
      editing: this.editingId === `vb-${b.id}`
    }));
  }

  handleEditCampusCodes(event) {
    const c = this.setup.vtuCampuses.find(
      (x) => x.id === event.currentTarget.dataset.id
    );
    this.editingId = `vc-${c.id}`;
    this.draft = { ...c };
  }

  handleEditBranchCode(event) {
    const b = this.setup.vtuBranches.find(
      (x) => x.id === event.currentTarget.dataset.id
    );
    this.editingId = `vb-${b.id}`;
    this.draft = { ...b };
  }

  async handleSaveCampusCodes() {
    await this.save(
      () =>
        saveCampusCodes({
          campus: {
            id: this.draft.id,
            region: this.draft.region,
            college: this.draft.college
          }
        }),
      "VTU codes saved"
    );
  }

  async handleSaveBranchCode() {
    await this.save(
      () =>
        saveBranchCode({
          branch: { id: this.draft.id, vtuCode: this.draft.vtuCode }
        }),
      "VTU branch code saved"
    );
  }

  handleUsnFile(event) {
    const file = event.target.files?.[0];
    this.usnResult = undefined;
    if (!file) {
      return;
    }
    this.usnFileName = file.name;
    const reader = new FileReader();
    reader.onload = () => {
      this.usnCsv = reader.result;
    };
    reader.readAsText(file);
  }

  get cannotCheckUsns() {
    return !this.usnCsv || this.isSaving;
  }

  get usnRows() {
    return (this.usnResult?.rows || []).map((r) => ({
      ...r,
      key: `${r.line}`,
      mark: r.ok ? "✔" : "✖",
      markClass: r.ok ? "total ok" : "total bad"
    }));
  }

  get usnSummary() {
    if (!this.usnResult) {
      return "";
    }
    const verb = this.usnResult.saved ? "saved" : "ready to save";
    return `${this.usnResult.accepted} ${verb}, ${this.usnResult.rejected} rejected`;
  }

  get canSaveUsns() {
    return Boolean(
      this.usnResult && !this.usnResult.saved && this.usnResult.accepted > 0
    );
  }

  get hasRejectedUsns() {
    return Boolean(this.usnResult?.rejected);
  }

  async handleCheckUsns() {
    await this.runUpload(false);
  }

  async handleSaveUsns() {
    await this.runUpload(true);
  }

  async runUpload(saveValid) {
    this.isSaving = true;
    try {
      this.usnResult = await uploadUsns({ csv: this.usnCsv, saveValid });
      if (saveValid) {
        toast(this, "USNs saved", this.usnSummary, "success");
      }
    } catch (error) {
      toast(this, "Not checked", reduceErrors(error).join(" "), "error");
    } finally {
      this.isSaving = false;
    }
  }

  /** The rejected rows with their reason, as a CSV to fix and upload again. */
  handleDownloadRejected() {
    const lines = ["Enrolment Number,USN,Reason"];
    this.usnResult.rows
      .filter((r) => !r.ok)
      .forEach((r) =>
        lines.push(
          [
            r.enrolmentNumber,
            r.usn || "",
            `"${(r.reason || "").replace(/"/g, "'")}"`
          ].join(",")
        )
      );
    const link = document.createElement("a");
    link.href = `data:text/csv;charset=utf-8,${encodeURIComponent(lines.join("\n"))}`;
    link.download = "usn-rejected.csv";
    link.click();
  }

  // ------------------------------------------------------------- fees

  get showFees() {
    return this.activeTab === "fees";
  }

  get courseOptions() {
    const seen = new Map();
    (this.setup?.rows || []).forEach((r) => seen.set(r.courseId, r.branch));
    return [...seen].map(([value, label]) => ({ label, value }));
  }

  get yearOptions() {
    const years = new Set((this.setup?.rows || []).map((r) => r.academicYear));
    const sorted = [...years].sort();
    if (sorted.length) {
      sorted.push(nextYear(sorted[sorted.length - 1]));
    }
    return sorted.map((y) => ({ label: y, value: y }));
  }

  get studyYearOptions() {
    return [
      { label: "All years of study", value: "" },
      { label: "Year 1", value: "1" },
      { label: "Year 2", value: "2" },
      { label: "Year 3", value: "3" },
      { label: "Year 4", value: "4" }
    ];
  }

  get feeColumns() {
    return (this.fees?.quotas || []).map((q, i) => ({
      key: `c${i}`,
      name: q.name
    }));
  }

  get feeRows() {
    const rows = this.feeEditing ? this.feeDraft : this.fees?.rows || [];
    return rows.map((r, ri) => ({
      key: `${r.feeType}|${r.frequency}`,
      label: `${r.feeType} · ${r.frequency}`,
      cells: r.cells.map((c, ci) => ({
        key: `${ri}-${ci}`,
        row: ri,
        col: ci,
        amount: c.amount,
        placeholder: c.fallback == null ? "" : `${c.fallback}`,
        display:
          c.amount != null
            ? `${c.amount}`
            : c.fallback != null
              ? `uses ${c.fallback}`
              : "—",
        displayClass: c.amount != null ? "amount" : "amount kem-muted"
      }))
    }));
  }

  async loadFees() {
    if (!this.feeCourse || !this.feeYear) {
      return;
    }
    try {
      this.fees = await getFees({
        courseId: this.feeCourse,
        academicYear: this.feeYear,
        yearOfStudy: this.feeStudyYear ? Number(this.feeStudyYear) : null
      });
      this.feeEditing = false;
    } catch (error) {
      toast(this, "Fees not loaded", reduceErrors(error).join(" "), "error");
    }
  }

  handleFeeCourse(event) {
    this.feeCourse = event.detail.value;
    this.loadFees();
  }
  handleFeeYear(event) {
    this.feeYear = event.detail.value;
    this.loadFees();
  }
  handleFeeStudyYear(event) {
    this.feeStudyYear = event.detail.value;
    this.loadFees();
  }
  handleFeeStarts(event) {
    this.feeStarts = event.target.value;
  }

  handleEditFees() {
    this.feeDraft = JSON.parse(JSON.stringify(this.fees.rows));
    this.feeEditing = true;
  }

  handleCancelFees() {
    this.feeEditing = false;
  }

  handleFeeCell(event) {
    const row = Number(event.target.dataset.row);
    const col = Number(event.target.dataset.col);
    const value = event.target.value;
    const draft = JSON.parse(JSON.stringify(this.feeDraft));
    draft[row].cells[col].amount = value === "" ? null : Number(value);
    this.feeDraft = draft;
  }

  /** Every quota column gets the default (CET) amount of its row. */
  handleCopyFromCet() {
    const draft = JSON.parse(JSON.stringify(this.feeDraft));
    draft.forEach((r) => {
      const standard = r.cells[0].amount ?? r.cells[0].fallback;
      r.cells.forEach((c, i) => {
        if (i > 0) {
          c.amount = standard;
        }
      });
    });
    this.feeDraft = draft;
  }

  /** Last academic year's amounts, cell by cell, into this year's draft. */
  async handleCopyLastYear() {
    try {
      const last = await getFees({
        courseId: this.feeCourse,
        academicYear: previousYear(this.feeYear),
        yearOfStudy: this.feeStudyYear ? Number(this.feeStudyYear) : null
      });
      const draft = JSON.parse(JSON.stringify(this.feeDraft));
      last.rows.forEach((lr) => {
        let target = draft.find(
          (r) => r.feeType === lr.feeType && r.frequency === lr.frequency
        );
        if (!target) {
          target = {
            feeType: lr.feeType,
            frequency: lr.frequency,
            cells: lr.cells.map((c) => ({ ...c, amount: null }))
          };
          draft.push(target);
        }
        lr.cells.forEach((lc) => {
          const cell = target.cells.find(
            (c) => (c.quotaId || null) === (lc.quotaId || null)
          );
          if (cell && lc.amount != null) {
            cell.amount = lc.amount;
          }
        });
      });
      this.feeDraft = draft;
      toast(
        this,
        `Copied the ${previousYear(this.feeYear)} fees`,
        "Check them and save.",
        "info"
      );
    } catch (error) {
      toast(this, "Not copied", reduceErrors(error).join(" "), "error");
    }
  }

  async handleSaveFees() {
    const inputs = [...this.template.querySelectorAll("lightning-input.fee")];
    if (!inputs.every((i) => i.reportValidity())) {
      return;
    }
    this.isSaving = true;
    try {
      this.fees = await saveFees({
        request: {
          courseId: this.feeCourse,
          academicYear: this.feeYear,
          yearOfStudy: this.feeStudyYear ? Number(this.feeStudyYear) : null,
          effectiveFrom: this.feeStarts,
          rows: this.feeDraft.map((r) => ({
            feeType: r.feeType,
            frequency: r.frequency,
            cells: r.cells.map((c) => ({
              quotaId: c.quotaId || null,
              amount: c.amount
            }))
          }))
        }
      });
      this.feeEditing = false;
      toast(
        this,
        "Fees saved",
        `New amounts apply from ${this.feeStarts}.`,
        "success"
      );
    } catch (error) {
      toast(this, "Not saved", reduceErrors(error).join(" "), "error");
    } finally {
      this.isSaving = false;
    }
  }

  handleEditIntake(event) {
    const row = this.setup.rows.find(
      (r) => r.id === event.currentTarget.dataset.id
    );
    this.editingId = row.id;
    this.draft = {
      id: row.id,
      intakeRegular: row.intakeRegular,
      intakeLateral: row.intakeLateral,
      admissionsOpen: row.admissionsOpen,
      deanExceptionsAllowed: row.deanExceptionsAllowed,
      lateralBasis: row.lateralBasis || "Seats",
      lateralPercentage:
        row.lateralPercentage ?? percentOf(row.intakeRegular, row.intakeLateral)
    };
  }

  handleEditRule(event) {
    const id = event.currentTarget.dataset.id;
    const row = this.ruleRows.find((r) => r.ruleId === id);
    this.editingId = id;
    this.draft = {
      ruleId: id,
      minPercentage: row.minPercentage,
      entrances: row.entrances.map((e) => ({
        exam: e.exam,
        maxRank: e.maxRank
      }))
    };
  }

  /** Typing the percentage fills the seats, and the other way round. */
  handleLateralPercent(event) {
    const pct = event.target.value;
    this.draft = {
      ...this.draft,
      lateralBasis: "Percentage",
      lateralPercentage: pct,
      intakeLateral: seatsFor(this.draft.intakeRegular, pct)
    };
  }

  handleLateralSeats(event) {
    const seats = event.target.value;
    this.draft = {
      ...this.draft,
      lateralBasis: "Seats",
      intakeLateral: seats,
      lateralPercentage: percentOf(this.draft.intakeRegular, seats)
    };
  }

  handleRegularSeats(event) {
    const regular = event.target.value;
    const next = { ...this.draft, intakeRegular: regular };
    if (next.lateralBasis === "Percentage") {
      next.intakeLateral = seatsFor(regular, next.lateralPercentage);
    } else {
      next.lateralPercentage = percentOf(regular, next.intakeLateral);
    }
    this.draft = next;
  }

  get lateralHint() {
    return this.draft.lateralBasis === "Percentage"
      ? "Set by percentage: the seats follow the regular seats."
      : "Set by number of seats.";
  }

  handleDraft(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.target.value;
    this.draft = { ...this.draft, [field]: value };
  }

  handleRank(event) {
    const exam = event.target.dataset.exam;
    const value = event.target.value;
    const maxRank = value === "" ? null : Number(value);
    this.draft = {
      ...this.draft,
      entrances: this.draft.entrances.map((e) => {
        if (e.exam !== exam) {
          return e;
        }
        return { ...e, maxRank };
      })
    };
  }

  handleCancel() {
    this.editingId = undefined;
  }

  async handleSaveIntake() {
    await this.save(
      () =>
        saveIntake({
          change: {
            ...this.draft,
            intakeRegular: Number(this.draft.intakeRegular),
            intakeLateral: Number(this.draft.intakeLateral),
            lateralPercentage:
              this.draft.lateralPercentage === "" ||
              this.draft.lateralPercentage == null
                ? null
                : Number(this.draft.lateralPercentage)
          }
        }),
      "Seats saved"
    );
  }

  async handleSaveRule() {
    await this.save(
      () =>
        saveRule({
          change: {
            ruleId: this.draft.ruleId,
            minPercentage: Number(this.draft.minPercentage),
            entrances: this.draft.entrances
          }
        }),
      "Eligibility rule saved as a new version"
    );
  }

  async save(action, message) {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    if (!inputs.every((i) => i.reportValidity())) {
      return;
    }
    this.isSaving = true;
    try {
      this.setup = await action();
      this.editingId = undefined;
      toast(this, message, "", "success");
    } catch (error) {
      toast(this, "Not saved", reduceErrors(error).join(" "), "error");
    } finally {
      this.isSaving = false;
    }
  }
}
