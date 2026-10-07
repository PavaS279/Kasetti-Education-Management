import { api } from "lwc";
import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/FamilySetupController.getChoices";
import findMatches from "@salesforce/apex/FamilySetupController.findMatches";
import createFamily from "@salesforce/apex/FamilySetupController.createFamily";
import { reduceErrors } from "c/kemUtils";

const STEPS = [
  { value: "family", label: "Parents" },
  { value: "learners", label: "Children" },
  { value: "check", label: "Check and save" }
];
const RELATIONSHIPS = [
  "Mother",
  "Father",
  "Guardian",
  "Grandparent",
  "Sibling",
  "Other"
].map((v) => ({ label: v, value: v }));
const LANGUAGES = [
  "English",
  "Kannada",
  "Hindi",
  "Tamil",
  "Telugu",
  "Malayalam",
  "Marathi",
  "Bengali",
  "Other"
].map((v) => ({ label: v, value: v }));
const CHANNELS = ["WhatsApp", "SMS", "Email", "Phone"].map((v) => ({
  label: v,
  value: v
}));
const NEXT_STEPS = [
  { label: "Just add", value: "none" },
  { label: "Enrol in a class now", value: "enrol" },
  { label: "Start an application", value: "apply" }
];

let personKey = 0;
const newGuardian = (relationship = "Mother") => ({
  key: `g-${++personKey}`,
  firstName: "",
  lastName: "",
  email: "",
  phone: "",
  relationship,
  isFeePayer: false,
  preferredLanguage: "English",
  preferredChannel: "WhatsApp",
  existingAccountId: null
});
const newLearner = (lastName = "") => ({
  key: `l-${++personKey}`,
  firstName: "",
  lastName,
  birthdate: undefined,
  school: "",
  nextStep: "none",
  offeringId: undefined,
  courseId: undefined,
  existingAccountId: null
});

/**
 * New family (walk-in): parents, children and each child's next step
 * (enrol now or apply), with a check for people who already exist before
 * anything is saved. Resolves to the result ({ learnerIds, guardianIds,
 * enrolmentIds, applicationIds, created, reused }) or null.
 */
export default class KemFamilyModal extends LightningModal {
  @api branchId;
  steps = STEPS;
  step = "family";
  relationshipOptions = RELATIONSHIPS;
  languageOptions = LANGUAGES;
  channelOptions = CHANNELS;
  nextStepOptions = NEXT_STEPS;
  branchOptions = [];
  courseOptions = [];
  classes = [];
  canEnrol = false;
  canApply = false;
  form = { branchId: undefined, street: "", city: "Bengaluru", postalCode: "" };
  guardians = [newGuardian("Mother"), newGuardian("Father")];
  learners = [newLearner()];
  matches = [];
  checked = false;
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "New family";
  }

  async connectedCallback() {
    try {
      await this.loadChoices(this.branchId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  async loadChoices(branchId) {
    const c = await getChoices({ branchId: branchId || null });
    this.branchOptions = (c.branches || []).map((b) => ({
      label: b.label,
      value: b.value
    }));
    this.courseOptions = (c.courses || []).map((o) => ({
      label: o.detail ? `${o.label} (${o.detail})` : o.label,
      value: o.value
    }));
    this.classes = c.classes || [];
    this.canEnrol = Boolean(c.canEnrol);
    this.canApply = Boolean(c.canApply);
    if (!this.form.branchId) {
      this.form = { ...this.form, branchId: branchId || c.defaultBranchId };
    }
  }

  // ------------------------------------------------------------ steps

  get stepIndex() {
    return STEPS.findIndex((s) => s.value === this.step);
  }
  get isFamily() {
    return this.step === "family";
  }
  get isLearners() {
    return this.step === "learners";
  }
  get isCheck() {
    return this.step === "check";
  }
  get showBack() {
    return this.stepIndex > 0;
  }

  get stepProblem() {
    if (this.isFamily) {
      if (!this.form.branchId) return "Choose the branch.";
      const named = this.namedGuardians;
      if (named.some((g) => !g.email.trim() && !g.phone.trim())) {
        return "Enter an email or mobile number for each parent.";
      }
    }
    if (this.isLearners) {
      const named = this.namedLearners;
      if (!named.length) return "Add at least one child.";
      if (named.some((l) => !l.birthdate))
        return "Enter each child's date of birth.";
      if (named.some((l) => l.nextStep === "enrol" && !l.offeringId))
        return "Choose the class for each child being enrolled.";
      if (named.some((l) => l.nextStep === "apply" && !l.courseId))
        return "Choose the course for each application.";
    }
    return undefined;
  }

  validInputs() {
    return [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ].reduce((ok, i) => i.reportValidity() && ok, true);
  }

  async handleNext() {
    this.errorMessage = this.stepProblem;
    if (this.errorMessage || !this.validInputs()) {
      return;
    }
    if (this.isFamily) {
      // Children usually share the family name.
      const last = this.namedGuardians[0]?.lastName;
      if (last) {
        this.learners = this.learners.map((l) => {
          return l.lastName ? l : { ...l, lastName: last };
        });
      }
    }
    this.step = STEPS[this.stepIndex + 1].value;
    if (this.isCheck) {
      await this.runCheck();
    }
  }

  handleBack() {
    this.errorMessage = undefined;
    this.step = STEPS[this.stepIndex - 1].value;
  }

  handleCancel() {
    this.close(null);
  }

  // ------------------------------------------------------------ fields

  async handleForm(event) {
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.form = { ...this.form, [field]: value };
    if (field === "branchId") {
      this.learners = this.learners.map((l) => ({
        ...l,
        offeringId: undefined
      }));
      try {
        await this.loadChoices(value);
      } catch (error) {
        this.errorMessage = reduceErrors(error).join(" ");
      }
    }
  }

  readValue(event) {
    if (event.target.type === "checkbox" || event.target.type === "toggle") {
      return event.target.checked;
    }
    return event.detail?.value !== undefined
      ? event.detail.value
      : event.target.value;
  }

  handleGuardian(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    const value = this.readValue(event);
    this.guardians = this.guardians.map((g, i) => {
      if (field === "isFeePayer" && value) {
        // One fee payer.
        return { ...g, isFeePayer: i === index };
      }
      return i === index ? { ...g, [field]: value } : g;
    });
    this.checked = false;
  }

  handleLearner(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    const value = this.readValue(event);
    this.learners = this.learners.map((l, i) => {
      return i === index ? { ...l, [field]: value } : l;
    });
    this.checked = false;
  }

  handleAddGuardian() {
    this.guardians = [...this.guardians, newGuardian("Guardian")];
  }
  handleRemoveGuardian(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.guardians = this.guardians.filter((_, i) => i !== index);
  }
  handleAddLearner() {
    this.learners = [
      ...this.learners,
      newLearner(this.namedGuardians[0]?.lastName || "")
    ];
  }
  handleRemoveLearner(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.learners = this.learners.filter((_, i) => i !== index);
  }

  get namedGuardians() {
    return this.guardians.filter(
      (g) => g.existingAccountId || g.lastName.trim()
    );
  }
  get namedLearners() {
    return this.learners.filter(
      (l) => l.existingAccountId || l.lastName.trim()
    );
  }

  get guardianRows() {
    return this.guardians.map((g, index) => ({
      ...g,
      index,
      number: index + 1,
      canRemove: this.guardians.length > 1
    }));
  }

  get nextStepChoices() {
    return NEXT_STEPS.filter(
      (o) =>
        o.value === "none" ||
        (o.value === "enrol" ? this.canEnrol : this.canApply)
    );
  }

  get learnerRows() {
    return this.learners.map((l, index) => {
      const classOptions = this.classes
        .filter((c) => !l.courseId || c.detail === l.courseId)
        .map((c) => ({ label: c.label, value: c.value }));
      return {
        ...l,
        index,
        number: index + 1,
        canRemove: this.learners.length > 1,
        isEnrol: l.nextStep === "enrol",
        isApply: l.nextStep === "apply",
        classOptions,
        noClasses: !classOptions.length
      };
    });
  }

  // ------------------------------------------------------------ check and save

  get request() {
    const g = this.namedGuardians.map((p) => ({
      existingAccountId: p.existingAccountId,
      firstName: p.firstName.trim(),
      lastName: p.lastName.trim(),
      email: p.email.trim(),
      phone: p.phone.trim(),
      relationship: p.relationship,
      isFeePayer: p.isFeePayer,
      preferredLanguage: p.preferredLanguage,
      preferredChannel: p.preferredChannel
    }));
    const l = this.namedLearners.map((p) => ({
      existingAccountId: p.existingAccountId,
      firstName: p.firstName.trim(),
      lastName: p.lastName.trim(),
      birthdate: p.birthdate,
      school: p.school.trim(),
      nextStep: p.nextStep,
      offeringId: p.nextStep === "enrol" ? p.offeringId : null,
      courseId: p.nextStep === "apply" ? p.courseId : null
    }));
    return {
      branchId: this.form.branchId,
      street: this.form.street,
      city: this.form.city,
      postalCode: this.form.postalCode,
      guardians: g,
      learners: l
    };
  }

  async runCheck() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.matches = await findMatches({ request: this.request });
      this.checked = true;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  /** The person at a request index for a kind. */
  personFor(kind, index) {
    const list = kind === "guardian" ? this.namedGuardians : this.namedLearners;
    return list[index];
  }

  get matchRows() {
    return (this.matches || []).map((m) => {
      const person = this.personFor(m.kind, m.index);
      const using = person?.existingAccountId === m.accountId;
      return {
        ...m,
        key: `${m.kind}-${m.index}`,
        entered: person ? `${person.firstName} ${person.lastName}`.trim() : "",
        kindLabel: m.kind === "guardian" ? "Parent" : "Child",
        using,
        useLabel: using ? "Using existing" : "Use existing",
        useVariant: using ? "brand" : "neutral"
      };
    });
  }

  get hasMatches() {
    return this.matchRows.length > 0;
  }

  handleUseExisting(event) {
    const { kind, index, account } = event.currentTarget.dataset;
    const person = this.personFor(kind, Number(index));
    const update = (list) =>
      list.map((p) => {
        if (p.key !== person.key) return p;
        return {
          ...p,
          existingAccountId: p.existingAccountId === account ? null : account
        };
      });
    if (kind === "guardian") {
      this.guardians = update(this.guardians);
    } else {
      this.learners = update(this.learners);
    }
  }

  get summary() {
    const n = (count, word) => `${count} ${word}${count === 1 ? "" : "s"}`;
    const reuse = this.namedGuardians
      .concat(this.namedLearners)
      .filter((p) => p.existingAccountId).length;
    const enrol = this.namedLearners.filter(
      (l) => l.nextStep === "enrol"
    ).length;
    const apply = this.namedLearners.filter(
      (l) => l.nextStep === "apply"
    ).length;
    const parts = [
      n(this.namedGuardians.length, "parent"),
      `${this.namedLearners.length} ${this.namedLearners.length === 1 ? "child" : "children"}`
    ];
    if (reuse) parts.push(`${reuse} already on file`);
    if (enrol)
      parts.push(
        `${enrol} enrolled now (first invoice follows the billing run)`
      );
    if (apply) parts.push(n(apply, "application"));
    return parts.join(" · ");
  }

  get cannotSave() {
    return this.isBusy || !this.checked;
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await createFamily({ request: this.request });
      this.close(result);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
