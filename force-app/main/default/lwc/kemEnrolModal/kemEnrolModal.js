import { api } from "lwc";
import LightningModal from "lightning/modal";
import CURRENCY from "@salesforce/i18n/currency";
import searchLearners from "@salesforce/apex/EnrolmentController.searchLearners";
import getEnrollableClasses from "@salesforce/apex/EnrolmentController.getEnrollableClasses";
import previewEnrolment from "@salesforce/apex/EnrolmentController.previewEnrolment";
import enrol from "@salesforce/apex/EnrolmentController.enrol";
import { reduceErrors, initials } from "c/kemUtils";

const STEPS = ["Learner", "Class", "Review"];
const DELAY = 300;

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "";
}

/**
 * Enrolment wizard. Pass learnerId/learnerName to skip the learner step,
 * offeringId to pre-select a class, courseId/branchId to filter classes, and
 * applicationId to enrol from an accepted offer. Resolves to the result or null.
 */
export default class KemEnrolModal extends LightningModal {
  @api label = "Enrol learner";
  @api learnerId;
  @api learnerName;
  @api offeringId;
  @api courseId;
  @api branchId;
  @api applicationId;

  currencyCode = CURRENCY;
  step = 0;
  searchTerm = "";
  learners = [];
  classes = [];
  selectedClassId;
  discountCode = "";
  preview;
  errorMessage;
  isBusy = false;
  timer;
  selectedLearnerId;
  selectedLearnerName;

  connectedCallback() {
    this.selectedClassId = this.offeringId;
    this.selectedLearnerId = this.learnerId;
    this.selectedLearnerName = this.learnerName;
    if (this.selectedLearnerId) {
      this.step = 1;
      this.loadClasses();
    }
  }

  get stepItems() {
    return STEPS.map((label, index) => ({
      index,
      number: index + 1,
      label,
      className: `step${index === this.step ? " step_current" : ""}${index < this.step ? " step_done" : ""}`
    }));
  }
  get isLearnerStep() {
    return this.step === 0;
  }
  get isClassStep() {
    return this.step === 1;
  }
  get isReviewStep() {
    return this.step === 2;
  }
  get canGoBack() {
    return this.step > (this.learnerId ? 1 : 0);
  }
  get isNextDisabled() {
    return (
      this.isBusy ||
      (this.isLearnerStep && !this.selectedLearnerId) ||
      (this.isClassStep && !this.selectedClassId)
    );
  }
  get isConfirmDisabled() {
    return this.isBusy || !this.preview || this.preview.blockers.length > 0;
  }
  get allWarnings() {
    return this.preview
      ? [...this.preview.blockers, ...this.preview.quote.warnings]
      : [];
  }
  get noClasses() {
    return this.classes.length === 0;
  }

  get learnerOptions() {
    return this.learners.map((l) => ({
      ...l,
      initials: initials(l.Name),
      detail: [l.PersonEmail, l.PersonMobilePhone].filter(Boolean).join(" · "),
      selected: l.Id === this.selectedLearnerId ? "true" : "false",
      className: `option${l.Id === this.selectedLearnerId ? " option_selected" : ""}`
    }));
  }

  get classOptions() {
    return this.classes.map((c) => {
      const capacity = c.EnrollmentCapacity || 0;
      const taken = c.Seats_Taken__c || 0;
      const pct = capacity
        ? Math.min(100, Math.round((100 * taken) / capacity))
        : 0;
      return {
        ...c,
        courseLabel: c.LearningCourse?.Name || "",
        branchLabel: c.Branch__r?.Name || "No branch",
        period: `${formatDate(c.StartDate)} – ${formatDate(c.EndDate)}`,
        seatLabel: capacity
          ? `${capacity - taken} of ${capacity} seats left`
          : "Unlimited",
        barStyle: `width: ${pct}%`,
        selected: c.Id === this.selectedClassId ? "true" : "false",
        className: `option class-option${c.Id === this.selectedClassId ? " option_selected" : ""}`
      };
    });
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
    clearTimeout(this.timer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(async () => {
      try {
        this.learners = await searchLearners({ term: this.searchTerm });
      } catch (error) {
        this.errorMessage = reduceErrors(error).join(" ");
      }
    }, DELAY);
  }

  handlePickLearner(event) {
    this.selectedLearnerId = event.currentTarget.dataset.id;
    this.selectedLearnerName = event.currentTarget.dataset.name;
  }

  handlePickClass(event) {
    this.selectedClassId = event.currentTarget.dataset.id;
  }

  handleCode(event) {
    this.discountCode = event.target.value;
    clearTimeout(this.timer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(() => this.loadPreview(), DELAY);
  }

  async loadClasses() {
    this.isBusy = true;
    try {
      this.classes = await getEnrollableClasses({
        courseId: this.courseId || null,
        branchId: this.branchId || null
      });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  async loadPreview() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      this.preview = await previewEnrolment({ request: this.buildRequest() });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  buildRequest() {
    return {
      learnerAccountId: this.selectedLearnerId,
      offeringId: this.selectedClassId,
      applicationId: this.applicationId || null,
      discountCode: this.discountCode
    };
  }

  async handleNext() {
    this.errorMessage = undefined;
    this.step += 1;
    if (this.step === 1) {
      await this.loadClasses();
    } else if (this.step === 2) {
      await this.loadPreview();
    }
  }

  handleBack() {
    this.errorMessage = undefined;
    this.step -= 1;
  }

  handleCancel() {
    this.close(null);
  }

  async handleConfirm() {
    this.isBusy = true;
    this.disableClose = true;
    this.errorMessage = undefined;
    try {
      const result = await enrol({ request: this.buildRequest() });
      this.disableClose = false;
      this.close(result);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
      this.disableClose = false;
    } finally {
      this.isBusy = false;
    }
  }
}
