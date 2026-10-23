import { LightningElement } from "lwc";
import getFormData from "@salesforce/apex/PublicEnquiryController.getFormData";
import submit from "@salesforce/apex/PublicEnquiryController.submit";

const EMPTY_FORM = Object.freeze({
  firstName: "",
  lastName: "",
  birthdate: "",
  email: "",
  phone: "",
  guardianFirstName: "",
  guardianLastName: "",
  guardianRelationship: "",
  guardianEmail: "",
  guardianPhone: "",
  branchCode: "",
  courseExternalId: "",
  deliveryMode: "",
  referralCode: "",
  message: "",
  website: "",
  privacyConsent: false
});

export default class KemPublicEnquiry extends LightningElement {
  form = { ...EMPTY_FORM };
  branchOptions = [];
  courseOptions = [{ label: "Not sure yet", value: "" }];
  relationshipOptions = [{ label: "Select relationship", value: "" }];
  deliveryModeOptions = [{ label: "No preference", value: "" }];
  isLoading = true;
  isSaving = false;
  isComplete = false;
  loadError;
  submitError;
  reference;
  formStartedAt = Date.now();
  submissionId = this.newSubmissionId();

  connectedCallback() {
    this.loadFormData();
  }

  /** College admission or learning-centre courses; chosen on the first screen. */
  interest;

  get isChoosing() {
    return !this.interest;
  }

  get isCollege() {
    return this.interest === "college";
  }

  chooseInterest(event) {
    this.interest = event.currentTarget.dataset.interest;
  }

  chooseAgain() {
    this.interest = undefined;
  }

  get today() {
    return new Date().toISOString().slice(0, 10);
  }

  get submitLabel() {
    return this.isSaving ? "Submitting…" : "Submit enquiry";
  }

  async loadFormData() {
    try {
      const data = await getFormData();
      this.branchOptions = (data.branches || []).map((item) => ({ ...item }));
      this.courseOptions = [
        ...this.courseOptions,
        ...(data.courses || []).map((item) => ({ ...item }))
      ];
      this.relationshipOptions = [
        ...this.relationshipOptions,
        ...(data.relationships || []).map((item) => ({ ...item }))
      ];
      this.deliveryModeOptions = [
        ...this.deliveryModeOptions,
        ...(data.deliveryModes || []).map((item) => ({ ...item }))
      ];
    } catch (error) {
      this.loadError = this.errorMessage(
        error,
        "The enquiry form is temporarily unavailable. Please try again later."
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleChange(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.form = { ...this.form, [field]: value };
  }

  async handleSubmit(event) {
    event.preventDefault();
    this.submitError = undefined;
    const controls = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-textarea"
      )
    ];
    const valid = controls.reduce((result, control) => {
      control.reportValidity();
      return result && control.checkValidity();
    }, true);
    if (!valid) return;
    if (
      !this.form.email &&
      !this.form.phone &&
      !this.form.guardianEmail &&
      !this.form.guardianPhone
    ) {
      this.submitError =
        "Enter at least one learner or guardian email address or phone number.";
      return;
    }
    this.isSaving = true;
    try {
      const result = await submit({
        request: {
          ...this.form,
          birthdate: this.form.birthdate || null,
          formStartedAt: this.formStartedAt,
          submissionId: this.submissionId
        }
      });
      this.reference = result.reference;
      this.isComplete = true;
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (error) {
      this.submitError = this.errorMessage(
        error,
        "We could not submit your enquiry. Please try again."
      );
    } finally {
      this.isSaving = false;
    }
  }

  startAnother() {
    this.form = { ...EMPTY_FORM };
    this.reference = undefined;
    this.isComplete = false;
    this.submitError = undefined;
    this.formStartedAt = Date.now();
    this.submissionId = this.newSubmissionId();
  }

  newSubmissionId() {
    const bytes = new Uint32Array(4);
    window.crypto.getRandomValues(bytes);
    return `portal-${Array.from(bytes, (value) => value.toString(16).padStart(8, "0")).join("-")}`;
  }

  errorMessage(error, fallback) {
    return error?.body?.message || fallback;
  }
}
