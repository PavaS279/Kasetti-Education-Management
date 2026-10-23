import LightningModal from "lightning/modal";
import getAdmissionCatalogue from "@salesforce/apex/CollegeAdmissionController.getAdmissionCatalogue";
import getRequirements from "@salesforce/apex/CollegeAdmissionController.getRequirements";
import previewEligibility from "@salesforce/apex/CollegeAdmissionController.previewEligibility";
import createAdmission from "@salesforce/apex/CollegeAdmissionController.createAdmission";
import { reduceErrors } from "c/kemUtils";

const STEPS = [
  { value: "programme", label: "Programme" },
  { value: "marks", label: "Marks and cut-off" },
  { value: "student", label: "Student" },
  { value: "review", label: "Documents and fees" }
];
const ALL_STREAMS = ["Science", "Commerce", "Arts"];
const PREVIEW_DELAY = 400;

const money = (value) =>
  new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(value || 0);

function options(values) {
  return values.map((v) => ({ label: v, value: v }));
}

function ageOn(birthdate) {
  if (!birthdate) {
    return null;
  }
  const born = new Date(birthdate);
  const now = new Date();
  let age = now.getFullYear() - born.getFullYear();
  const beforeBirthday =
    now.getMonth() < born.getMonth() ||
    (now.getMonth() === born.getMonth() && now.getDate() < born.getDate());
  if (beforeBirthday) {
    age -= 1;
  }
  return age;
}

/**
 * Guided college admission for the desk: campus → programme → branch → route,
 * then only the marks that branch needs, checked live against the cut-off
 * before anything is saved. Resolves to the new admission Id, or null.
 */
export default class KemCollegeAdmissionWizard extends LightningModal {
  steps = STEPS;
  step = "programme";
  catalogue = [];
  campusId;
  programmeId;
  campusBranchId;
  route = "Regular";
  requirements = {};
  marks = {};
  preview;
  student = {};
  consent = false;
  errorMessage;
  isLoading = true;
  previewTimer;

  async connectedCallback() {
    try {
      this.catalogue = await getAdmissionCatalogue();
      if (this.catalogue.length === 1) {
        this.campusId = this.catalogue[0].id;
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
    this.isLoading = false;
  }

  // ------------------------------------------------------------ steps

  get isProgramme() {
    return this.step === "programme";
  }
  get isMarks() {
    return this.step === "marks";
  }
  get isStudent() {
    return this.step === "student";
  }
  get isReview() {
    return this.step === "review";
  }
  get canGoBack() {
    return this.step !== "programme";
  }

  get cannotContinue() {
    if (this.isLoading) {
      return true;
    }
    if (this.isProgramme) {
      return !this.campusBranchId || !this.requirements.open;
    }
    if (this.isMarks) {
      return this.preview?.status !== "Eligible";
    }
    if (this.isStudent) {
      return (
        !this.student.lastName || !this.student.birthdate || !this.student.phone
      );
    }
    return false;
  }

  get cannotCreate() {
    return this.isLoading || !this.consent;
  }

  handleNext() {
    const index = STEPS.findIndex((s) => s.value === this.step);
    this.step = STEPS[index + 1].value;
    this.errorMessage = undefined;
  }

  handleBack() {
    const index = STEPS.findIndex((s) => s.value === this.step);
    this.step = STEPS[index - 1].value;
    this.errorMessage = undefined;
  }

  handleCancel() {
    this.close(null);
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
      cutoff: b.cutoff || "not set",
      seatClass:
        b.seatsRegular > 0 ? "kem-badge tone-success" : "kem-badge tone-error",
      className:
        b.campusBranchId === this.campusBranchId
          ? "tile branch selected"
          : "tile branch"
    }));
  }

  get showRoute() {
    return Boolean(this.branch?.lateral);
  }

  get routeOptions() {
    return [
      { label: "Year 1 (regular)", value: "Regular" },
      { label: "Year 2 (lateral entry from Diploma)", value: "Lateral" }
    ];
  }

  get routeHelp() {
    return this.route === "Lateral"
      ? `Lateral entry: Diploma holders join in year 2. ${this.branch?.seatsLateral} lateral seats left.`
      : "Regular entry starts in year 1.";
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
    this.route = event.detail.value;
    this.loadRequirements();
  }

  resetBranch() {
    this.campusBranchId = undefined;
    this.requirements = {};
    this.preview = undefined;
  }

  async loadRequirements() {
    this.isLoading = true;
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
        sslc: this.marks.sslc,
        qualifying: this.marks.qualifying,
        rank: this.marks.rank,
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
      this.schedulePreview();
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
    this.isLoading = false;
  }

  // ------------------------------------------------------------ step 2

  get needsPuc() {
    return this.requirements.qualifyingLevel === "PUC";
  }

  get needsDiploma() {
    return this.requirements.qualifyingLevel === "Diploma";
  }

  get marksTitle() {
    if (this.needsPuc) {
      return "SSLC and PUC results";
    }
    if (this.needsDiploma) {
      return "SSLC and Diploma results";
    }
    return "SSLC result";
  }

  get streamOptions() {
    return options(ALL_STREAMS);
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
    this.schedulePreview();
  }

  handleMarkCombo(event) {
    this.marks = {
      ...this.marks,
      [event.target.dataset.field]: event.detail.value
    };
    this.schedulePreview();
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

  schedulePreview() {
    clearTimeout(this.previewTimer);
    if (!this.campusBranchId || !this.requirements.open) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.runPreview(), PREVIEW_DELAY);
  }

  async runPreview() {
    if (!this.qualifications().length) {
      this.preview = undefined;
      return;
    }
    try {
      this.preview = await previewEligibility({
        campusBranchId: this.campusBranchId,
        entryRoute: this.route,
        qualifications: this.qualifications(),
        entrances: this.entrances()
      });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
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

  get verdictTitle() {
    if (!this.preview) {
      return "Cut-off check";
    }
    return this.preview.status === "Eligible"
      ? "Eligible"
      : this.preview.status === "Not Eligible"
        ? "Not eligible for this branch"
        : "More details needed";
  }

  get verdictClass() {
    const status = this.preview?.status;
    if (status === "Eligible") {
      return "verdict kem-card ok";
    }
    return status === "Not Eligible"
      ? "verdict kem-card bad"
      : "verdict kem-card";
  }

  switchBranch(event) {
    const id = event.target.dataset.id;
    const target = this.campus.programmes
      .flatMap((p) => p.branches.map((b) => ({ programmeId: p.id, branch: b })))
      .find((x) => x.branch.campusBranchId === id);
    if (target) {
      this.programmeId = target.programmeId;
      this.campusBranchId = id;
      this.loadRequirements();
    }
  }

  // ------------------------------------------------------------ step 3

  get parentHint() {
    const age = ageOn(this.student.birthdate);
    return age !== null && age < 18
      ? "(recommended: the student is under 18)"
      : "(optional)";
  }

  get studentName() {
    return [this.student.firstName, this.student.lastName]
      .filter(Boolean)
      .join(" ");
  }

  handleStudent(event) {
    this.student = {
      ...this.student,
      [event.target.dataset.field]: event.target.value
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
      identity: d.sensitiveClass === "Identity",
      badge: d.required ? "Required" : "Optional",
      badgeClass: d.required ? "kem-badge tone-warning" : "kem-badge"
    }));
  }

  handleConsent(event) {
    this.consent = event.target.checked;
  }

  async handleCreate() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const result = await createAdmission({
        request: {
          ...this.student,
          campusBranchId: this.campusBranchId,
          entryRoute: this.route,
          qualifications: this.qualifications(),
          entrances: this.entrances(),
          consent: this.consent
        }
      });
      this.close(result.id);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
      this.isLoading = false;
    }
  }
}
