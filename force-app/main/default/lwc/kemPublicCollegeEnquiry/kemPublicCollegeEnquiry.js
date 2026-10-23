import { LightningElement } from "lwc";
import getCatalogue from "@salesforce/apex/CollegePublicController.getCatalogue";
import getRequirements from "@salesforce/apex/CollegePublicController.getRequirements";
import checkEligibility from "@salesforce/apex/CollegePublicController.checkEligibility";
import submit from "@salesforce/apex/PublicEnquiryController.submit";

const STEPS = [
  { value: "programme", label: "Programme" },
  { value: "marks", label: "Eligibility" },
  { value: "details", label: "Your details" },
  { value: "review", label: "Review" }
];
const STREAMS = ["Science", "Commerce", "Arts"];
const RELATIONSHIPS = [
  "Father",
  "Mother",
  "Guardian",
  "Grandparent",
  "Sibling",
  "Other"
];
const CHECK_DELAY = 450;

function options(values) {
  return values.map((v) => ({ label: v, value: v }));
}

function money(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(value || 0);
}

function ageOn(birthdate) {
  if (!birthdate) {
    return null;
  }
  const born = new Date(birthdate);
  const now = new Date();
  let age = now.getFullYear() - born.getFullYear();
  if (
    now.getMonth() < born.getMonth() ||
    (now.getMonth() === born.getMonth() && now.getDate() < born.getDate())
  ) {
    age -= 1;
  }
  return age;
}

/**
 * Public college admission enquiry: campus → programme → branch → route, then
 * only the marks that branch needs with a live cut-off self-check, contact
 * details and a review of documents and fees. Sends an enquiry to the admission
 * desk; nothing else is created.
 */
export default class KemPublicCollegeEnquiry extends LightningElement {
  step = "programme";
  catalogue = [];
  campusId;
  programmeId;
  campusBranchId;
  route = "Regular";
  requirements = {};
  marks = {};
  preview;
  form = { privacyConsent: false, website: "" };
  isBusy = true;
  isSaving = false;
  isComplete = false;
  errorMessage;
  reference;
  checkTimer;
  formStartedAt = Date.now();
  submissionId = this.newSubmissionId();

  async connectedCallback() {
    try {
      this.catalogue = (await getCatalogue()) || [];
      if (this.catalogue.length === 1) {
        this.campusId = this.catalogue[0].id;
      }
      if (!this.catalogue.length) {
        this.errorMessage = "Admissions are not open right now.";
      }
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "Programme information is not available right now."
      );
    }
    this.isBusy = false;
  }

  // ------------------------------------------------------------ steps

  get isProgramme() {
    return this.step === "programme";
  }
  get isMarks() {
    return this.step === "marks";
  }
  get isDetails() {
    return this.step === "details";
  }
  get isReview() {
    return this.step === "review";
  }

  get stepItems() {
    const current = STEPS.findIndex((s) => s.value === this.step);
    return STEPS.map((s, i) => ({
      ...s,
      number: i + 1,
      className:
        i === current ? "step current" : i < current ? "step done" : "step"
    }));
  }

  get backLabel() {
    return this.isProgramme ? "Back" : "Previous";
  }

  get cannotContinue() {
    if (this.isBusy) {
      return true;
    }
    if (this.isProgramme) {
      return !this.campusBranchId || !this.requirements.open;
    }
    if (this.isMarks) {
      return !this.qualifications().length;
    }
    if (this.isDetails) {
      return (
        !this.form.lastName ||
        !(this.form.phone || this.form.email || this.form.guardianPhone)
      );
    }
    return false;
  }

  get cannotSubmit() {
    return this.isSaving || !this.form.privacyConsent;
  }

  get submitLabel() {
    return this.isSaving ? "Sending…" : "Send enquiry";
  }

  handleNext() {
    const index = STEPS.findIndex((s) => s.value === this.step);
    this.step = STEPS[index + 1].value;
    this.errorMessage = undefined;
  }

  handleBack() {
    const index = STEPS.findIndex((s) => s.value === this.step);
    if (index === 0) {
      this.dispatchEvent(new CustomEvent("back"));
      return;
    }
    this.step = STEPS[index - 1].value;
    this.errorMessage = undefined;
  }

  // ------------------------------------------------------------ step 1

  get campus() {
    return this.catalogue.find((c) => c.id === this.campusId);
  }
  get programme() {
    return this.campus?.programmes.find((p) => p.id === this.programmeId);
  }
  get branch() {
    return this.programme?.branches.find(
      (b) => b.campusBranchId === this.campusBranchId
    );
  }

  get campusTiles() {
    return this.catalogue.map((c) => ({
      ...c,
      className: c.id === this.campusId ? "tile selected" : "tile"
    }));
  }

  get programmeTiles() {
    return (this.campus?.programmes || []).map((p) => ({
      ...p,
      count: p.branches.length,
      className: p.id === this.programmeId ? "tile selected" : "tile"
    }));
  }

  get branchTiles() {
    return (this.programme?.branches || []).map((b) => ({
      ...b,
      cutoff: b.cutoff || "on request",
      className:
        b.campusBranchId === this.campusBranchId ? "tile selected" : "tile"
    }));
  }

  get showRoute() {
    return Boolean(this.branch?.lateral);
  }

  get routeTiles() {
    return [
      { value: "Regular", label: "Year 1", help: "After PUC Science" },
      {
        value: "Lateral",
        label: "Year 2 (lateral entry)",
        help: "After a Diploma"
      }
    ].map((r) => ({
      ...r,
      className: r.value === this.route ? "tile selected" : "tile"
    }));
  }

  get routeLabel() {
    return this.route === "Lateral" ? "Year 2 (lateral entry)" : "Year 1";
  }

  pickCampus(event) {
    this.campusId = event.currentTarget.dataset.id;
    this.programmeId = undefined;
    this.resetBranch();
  }

  pickProgramme(event) {
    this.programmeId = event.currentTarget.dataset.id;
    this.resetBranch();
  }

  pickBranch(event) {
    this.campusBranchId = event.currentTarget.dataset.id;
    this.route = "Regular";
    this.loadRequirements();
  }

  pickRoute(event) {
    this.route = event.currentTarget.dataset.value;
    this.loadRequirements();
  }

  resetBranch() {
    this.campusBranchId = undefined;
    this.requirements = {};
    this.preview = undefined;
  }

  async loadRequirements() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.requirements = await getRequirements({
        campusBranchId: this.campusBranchId,
        entryRoute: this.route
      });
      if (!this.requirements.open) {
        this.errorMessage = this.requirements.message;
      }
      this.marks = {
        ...this.marks,
        stream:
          this.requirements.streams?.length === 1
            ? this.requirements.streams[0]
            : this.marks.stream,
        exam:
          this.requirements.entrances?.length === 1
            ? this.requirements.entrances[0].exam
            : this.marks.exam
      };
      this.preview = undefined;
      this.scheduleCheck();
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "Programme information is not available right now."
      );
    }
    this.isBusy = false;
  }

  // ------------------------------------------------------------ step 2

  get needsPuc() {
    return this.requirements.qualifyingLevel === "PUC";
  }
  get needsDiploma() {
    return this.requirements.qualifyingLevel === "Diploma";
  }
  get streamOptions() {
    return options(STREAMS);
  }
  get diplomaOptions() {
    const codes = this.requirements.diplomaBranchCodes || [];
    return options(codes.length ? codes : ["CS", "ME", "EE"]);
  }
  get examOptions() {
    return (this.requirements.entrances || []).map((e) => ({
      label: e.maxRank
        ? `${e.exam} (rank up to ${e.maxRank})`
        : `${e.exam} (any rank)`,
      value: e.exam
    }));
  }
  get selectedBranchName() {
    return this.branch?.name;
  }
  get selectedCampusName() {
    return this.campus?.name;
  }

  handleMark(event) {
    this.marks = {
      ...this.marks,
      [event.target.dataset.field]: event.target.value
    };
    this.scheduleCheck();
  }

  handleMarkCombo(event) {
    this.marks = {
      ...this.marks,
      [event.target.dataset.field]: event.detail.value
    };
    this.scheduleCheck();
  }

  qualifications() {
    const rows = [];
    if (this.marks.sslc) {
      rows.push({ level: "SSLC", percentage: Number(this.marks.sslc) });
    }
    if ((this.needsPuc || this.needsDiploma) && this.marks.qualifying) {
      rows.push({
        level: this.requirements.qualifyingLevel,
        stream: this.needsPuc ? this.marks.stream : null,
        branchCode: this.needsDiploma ? this.marks.diplomaBranch : null,
        percentage: Number(this.marks.qualifying)
      });
    }
    return rows;
  }

  entrances() {
    return this.requirements.entranceRequired &&
      this.marks.exam &&
      this.marks.rank
      ? [{ exam: this.marks.exam, rank: Number(this.marks.rank) }]
      : [];
  }

  scheduleCheck() {
    clearTimeout(this.checkTimer);
    if (!this.campusBranchId || !this.requirements.open) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.checkTimer = setTimeout(() => this.runCheck(), CHECK_DELAY);
  }

  async runCheck() {
    if (!this.qualifications().length) {
      this.preview = undefined;
      return;
    }
    try {
      this.preview = await checkEligibility({
        campusBranchId: this.campusBranchId,
        entryRoute: this.route,
        qualifications: this.qualifications(),
        entrances: this.entrances()
      });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "The eligibility check is not available right now."
      );
    }
  }

  get checks() {
    return (this.preview?.checks || []).map((c) => ({
      ...c,
      icon: c.passed ? "utility:success" : "utility:error",
      className: c.passed ? "check pass" : "check fail"
    }));
  }

  get hasSuggestions() {
    return Boolean(this.preview?.suggestions?.length);
  }

  get notEligible() {
    return this.preview?.status === "Not Eligible";
  }

  get verdictTitle() {
    if (!this.preview) {
      return "Eligibility check";
    }
    if (this.preview.status === "Eligible") {
      return "You meet the cut-off";
    }
    return this.notEligible
      ? "Below the cut-off for this branch"
      : "A few more details needed";
  }

  get verdictClass() {
    if (this.preview?.status === "Eligible") {
      return "verdict ok";
    }
    return this.notEligible ? "verdict bad" : "verdict";
  }

  switchBranch(event) {
    const id = event.target.dataset.id;
    const match = this.campus.programmes
      .flatMap((p) => p.branches.map((b) => ({ programmeId: p.id, branch: b })))
      .find((x) => x.branch.campusBranchId === id);
    if (match) {
      this.programmeId = match.programmeId;
      this.campusBranchId = id;
      this.loadRequirements();
    }
  }

  // ------------------------------------------------------------ step 3

  get today() {
    return new Date().toISOString().slice(0, 10);
  }

  get relationshipOptions() {
    return options(RELATIONSHIPS);
  }

  get parentHint() {
    const age = ageOn(this.form.birthdate);
    return age !== null && age < 18
      ? "(recommended for students under 18)"
      : "(optional)";
  }

  handleField(event) {
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;
    this.form = { ...this.form, [event.target.dataset.field]: value };
  }

  handleFieldCombo(event) {
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.detail.value
    };
  }

  // ------------------------------------------------------------ step 4

  get tuitionLabel() {
    return money(this.requirements.tuition);
  }
  get admissionFeeLabel() {
    return money(this.requirements.admissionFee);
  }
  get totalLabel() {
    return money(
      (this.requirements.tuition || 0) + (this.requirements.admissionFee || 0)
    );
  }

  get documentRows() {
    return (this.requirements.documents || []).map((d) => ({
      ...d,
      badge: d.required ? "Required" : "Optional",
      badgeClass: d.required ? "badge required" : "badge"
    }));
  }

  get reviewVerdict() {
    if (this.preview?.status === "Eligible") {
      return "✓ Your marks meet the published cut-off.";
    }
    if (this.notEligible) {
      return "Your marks are below the cut-off — the desk will advise you on other options.";
    }
    return "Eligibility will be confirmed by the admission desk.";
  }

  get reviewVerdictClass() {
    return this.preview?.status === "Eligible" ? "ok-text" : "muted";
  }

  /** The marks and self-check result travel to the desk inside the enquiry message. */
  summary() {
    const parts = [
      `College admission enquiry: ${this.branch.name}, ${this.campus.name}, ${this.routeLabel}.`
    ];
    this.qualifications().forEach((q) => {
      const detail = q.stream || q.branchCode;
      parts.push(`${q.level}${detail ? " " + detail : ""}: ${q.percentage}%`);
    });
    this.entrances().forEach((e) => parts.push(`${e.exam} rank ${e.rank}`));
    if (this.preview) {
      parts.push(`Self-check: ${this.preview.status} — ${this.preview.reason}`);
    }
    return parts.join(" ").slice(0, 2000);
  }

  async handleSubmit() {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const result = await submit({
        request: {
          firstName: this.form.firstName,
          lastName: this.form.lastName,
          birthdate: this.form.birthdate || null,
          email: this.form.email,
          phone: this.form.phone,
          guardianFirstName: this.form.guardianFirstName,
          guardianLastName: this.form.guardianLastName,
          guardianRelationship: this.form.guardianRelationship,
          guardianPhone: this.form.guardianPhone,
          branchCode: this.campus.code,
          courseExternalId: this.branch.externalId,
          message: this.summary(),
          website: this.form.website,
          privacyConsent: this.form.privacyConsent,
          formStartedAt: this.formStartedAt,
          submissionId: this.submissionId
        }
      });
      this.reference = result.reference;
      this.isComplete = true;
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (error) {
      this.errorMessage = this.messageOf(
        error,
        "We could not send your enquiry. Please try again."
      );
    }
    this.isSaving = false;
  }

  startAnother() {
    this.isComplete = false;
    this.step = "programme";
    this.form = { privacyConsent: false, website: "" };
    this.marks = {};
    this.preview = undefined;
    this.formStartedAt = Date.now();
    this.submissionId = this.newSubmissionId();
  }

  newSubmissionId() {
    const bytes = new Uint32Array(4);
    window.crypto.getRandomValues(bytes);
    return `portal-${Array.from(bytes, (value) => value.toString(16).padStart(8, "0")).join("-")}`;
  }

  messageOf(error, fallback) {
    return error?.body?.message || fallback;
  }
}
