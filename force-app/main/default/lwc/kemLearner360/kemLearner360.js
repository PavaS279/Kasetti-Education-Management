import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import LightningConfirm from "lightning/confirm";
import getLearner360 from "@salesforce/apex/Learner360Controller.getLearner360";
import endGuardianLink from "@salesforce/apex/Learner360Controller.endGuardianLink";
import updatePreferences from "@salesforce/apex/Learner360Controller.updatePreferences";
import GuardianModal from "c/kemGuardianModal";
import { reduceErrors, toast, toastError, initials, toneFor } from "c/kemUtils";

const DASH = "—";
const CHANNELS = ["Email", "SMS", "WhatsApp", "Phone"];
const LANGUAGES = [
  "English",
  "Hindi",
  "Kannada",
  "Tamil",
  "Telugu",
  "Malayalam",
  "Marathi",
  "Bengali",
  "Other"
];
const ACTIVE_STATUSES = ["Enrolled", "Facilitating", "On Hold"];

function statusClass(status) {
  if (["Enrolled", "Completed", "Application Decision"].includes(status)) {
    return "kem-badge kem-badge_success";
  }
  if (
    [
      "Withdrew",
      "Withdrawn",
      "Canceled",
      "Cancelled",
      "Dropped",
      "Failed",
      "Enrollment Failed"
    ].includes(status)
  ) {
    return "kem-badge kem-badge_danger";
  }
  if (
    ["On Hold", "Waitlisted", "In Review", "Ready For Decision"].includes(
      status
    )
  ) {
    return "kem-badge kem-badge_warning";
  }
  return "kem-badge kem-badge_info";
}

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : DASH;
}

export default class KemLearner360 extends NavigationMixin(LightningElement) {
  @api recordId;
  view;
  errorMessage;
  prefs = {};
  isSavingPrefs = false;
  wiredResult;

  @wire(getLearner360, { accountId: "$recordId" })
  wiredLearner(result) {
    this.wiredResult = result;
    if (result.data) {
      this.view = result.data;
      this.errorMessage = undefined;
      const p = result.data.person;
      this.prefs = {
        preferredChannel: p.Preferred_Channel__pc,
        preferredLanguage: p.Preferred_Language__pc,
        smsOptIn: p.SMS_Opt_In__pc,
        whatsAppOptIn: p.WhatsApp_Opt_In__pc,
        emailOptOut: p.PersonHasOptedOutOfEmail,
        emergencyInstructions: p.Emergency_Instructions__pc
      };
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get person() {
    return this.view.person;
  }
  get avatarInitials() {
    return initials(this.person.Name);
  }
  get avatarClass() {
    return `kem-avatar kem-avatar_lg ${toneFor(this.person.Name)}`;
  }
  get studentNumber() {
    return this.view.profile?.Student_Number__c;
  }
  get branchName() {
    return this.person.Branch__r?.Name;
  }
  get roleChips() {
    const role = this.person.KEM_Role__c;
    if (!role) {
      return [];
    }
    return role === "Learner and Guardian" ? ["Learner", "Guardian"] : [role];
  }
  get email() {
    return this.person.PersonEmail || DASH;
  }
  get phone() {
    return this.person.PersonMobilePhone || this.person.Phone || DASH;
  }
  get birthdate() {
    return formatDate(this.person.PersonBirthdate);
  }
  get emergencyInstructions() {
    return this.person.Emergency_Instructions__pc;
  }
  get isNotPerson() {
    return !this.person.IsPersonAccount;
  }
  get activeClassCount() {
    return this.view.enrolments.filter((e) =>
      ACTIVE_STATUSES.includes(e.ParticipationStatus)
    ).length;
  }

  decoratePerson(link) {
    return {
      ...link,
      initials: initials(link.name),
      avatarClass: `kem-avatar ${toneFor(link.name)}`,
      relationshipLabel: link.relationship || "Guardian",
      contactLine: [link.phone, link.email].filter(Boolean).join(" · ") || DASH,
      feePayerClass: link.isFeePayer
        ? "kem-badge kem-badge_success"
        : "kem-badge flag-off",
      portalClass: link.portalAccess
        ? "kem-badge kem-badge_info"
        : "kem-badge flag-off",
      emergencyClass: link.isEmergencyContact
        ? "kem-badge kem-badge_warning"
        : "kem-badge flag-off"
    };
  }

  get guardianCards() {
    return this.view.guardians.map((g) => this.decoratePerson(g));
  }
  get childCards() {
    return this.view.children.map((c) => this.decoratePerson(c));
  }
  get noGuardians() {
    return this.view.guardians.length === 0;
  }
  get hasSiblings() {
    return this.view.siblings.length > 0;
  }
  get applicationRows() {
    return this.view.applications.map((a) => ({
      ...a,
      courseLabel:
        a.Learning_Course__r?.Name ||
        a.Learning_Program__r?.Name ||
        "Course not selected",
      branchLabel: a.Branch__r?.Name || "No branch",
      appliedLabel: formatDate(a.AppliedDate),
      statusClass: statusClass(a.Status)
    }));
  }
  get noApplications() {
    return this.view.applications.length === 0;
  }
  get enrolmentRows() {
    return this.view.enrolments.map((e) => ({
      ...e,
      offeringLabel: e.CourseOffering?.Name || e.Name,
      periodLabel: `${formatDate(e.StartDate)} – ${formatDate(e.EndDate)}`,
      statusClass: statusClass(e.ParticipationStatus)
    }));
  }
  get noEnrolments() {
    return this.view.enrolments.length === 0;
  }
  get channelOptions() {
    return CHANNELS.map((c) => ({ label: c, value: c }));
  }
  get languageOptions() {
    return LANGUAGES.map((l) => ({ label: l, value: l }));
  }

  handleNavigate(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  async handleAddGuardian() {
    const result = await GuardianModal.open({
      size: "medium",
      label: "Add guardian",
      learnerId: this.recordId
    });
    if (result === "saved") {
      toast(this, "Guardian linked", "The guardian relationship was saved.");
      await refreshApex(this.wiredResult);
    }
  }

  async handleGuardianMenu(event) {
    const relationId = event.currentTarget.dataset.relation;
    const link = this.view.guardians.find((g) => g.relationId === relationId);
    if (event.detail.value === "edit") {
      const result = await GuardianModal.open({
        size: "small",
        label: `Edit ${link.name}`,
        learnerId: this.recordId,
        link
      });
      if (result === "saved") {
        toast(this, "Guardian updated", "The relationship was updated.");
        await refreshApex(this.wiredResult);
      }
      return;
    }
    const confirmed = await LightningConfirm.open({
      message: `End the relationship with ${link.name}? Portal access and fee-payer status through this link are removed. History is kept.`,
      variant: "header",
      theme: "warning",
      label: "End guardian relationship"
    });
    if (!confirmed) {
      return;
    }
    try {
      await endGuardianLink({ relationId });
      toast(
        this,
        "Relationship ended",
        `${link.name} is no longer linked as a guardian.`
      );
      await refreshApex(this.wiredResult);
    } catch (error) {
      toastError(this, error, "Relationship could not be ended");
    }
  }

  handlePref(event) {
    this.prefs = { ...this.prefs, [event.target.name]: event.detail.value };
  }

  handlePrefToggle(event) {
    this.prefs = { ...this.prefs, [event.target.name]: event.target.checked };
  }

  async handleSavePrefs() {
    this.isSavingPrefs = true;
    try {
      await updatePreferences({ accountId: this.recordId, input: this.prefs });
      toast(
        this,
        "Preferences saved",
        "Communication preferences were updated."
      );
      await refreshApex(this.wiredResult);
    } catch (error) {
      toastError(this, error, "Preferences could not be saved");
    } finally {
      this.isSavingPrefs = false;
    }
  }
}
