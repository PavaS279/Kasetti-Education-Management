import { LightningElement } from "lwc";
import getSetup from "@salesforce/apex/CollegeSetupController.getSetup";
import saveIntake from "@salesforce/apex/CollegeSetupController.saveIntake";
import saveRule from "@salesforce/apex/CollegeSetupController.saveRule";
import saveQuota from "@salesforce/apex/CollegeSetupController.saveQuota";
import saveSplit from "@salesforce/apex/CollegeSetupController.saveSplit";
import { reduceErrors, toast } from "c/kemUtils";

const TABS = [
  { label: "Seats & admissions", value: "intake" },
  { label: "Quotas", value: "quotas" },
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
      deanExceptionsAllowed: row.deanExceptionsAllowed
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
            intakeLateral: Number(this.draft.intakeLateral)
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
