import { api } from "lwc";
import LightningModal from "lightning/modal";
import searchLearners from "@salesforce/apex/EnrolmentController.searchLearners";
import joinWaitlist from "@salesforce/apex/WaitlistController.joinWaitlist";
import { reduceErrors, initials, toneFor } from "c/kemUtils";

const DELAY = 300;

/** Adds a learner to a full class's waitlist. Resolves to the new entry Id, or null. */
export default class KemWaitlistJoinModal extends LightningModal {
  @api offeringId;
  @api className;
  searchTerm = "";
  learners = [];
  selectedLearnerId;
  selectedLearnerName;
  priority = "0";
  discountCode = "";
  notes = "";
  errorMessage;
  isSaving = false;

  get heading() {
    return `Add to waitlist · ${this.className}`;
  }
  get priorityOptions() {
    return [
      { label: "Normal — first come, first served", value: "0" },
      {
        label: "Priority (for example a sibling of a current learner)",
        value: "1"
      },
      { label: "Urgent", value: "2" }
    ];
  }
  get learnerOptions() {
    return this.learners.map((l) => ({
      ...l,
      initials: initials(l.Name),
      avatarClass: `kem-avatar ${toneFor(l.Name)}`,
      selected: l.Id === this.selectedLearnerId ? "true" : "false",
      className: `option${l.Id === this.selectedLearnerId ? " option_selected" : ""}`,
      detail: l.PersonEmail || l.PersonMobilePhone || ""
    }));
  }
  get noMatches() {
    return this.searchTerm.length >= 2 && this.learners.length === 0;
  }
  get cannotSave() {
    return this.isSaving || !this.selectedLearnerId;
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
    clearTimeout(this.timer);
    if (this.searchTerm.length < 2) {
      this.learners = [];
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(async () => {
      try {
        this.learners = await searchLearners({ term: this.searchTerm });
      } catch (error) {
        this.errorMessage = reduceErrors(error).join(" ");
      }
    }, DELAY);
  }

  handlePick(event) {
    this.selectedLearnerId = event.currentTarget.dataset.id;
    this.selectedLearnerName = event.currentTarget.dataset.name;
  }
  handlePriority(event) {
    this.priority = event.detail.value;
  }
  handleCode(event) {
    this.discountCode = event.target.value;
  }
  handleNotes(event) {
    this.notes = event.target.value;
  }
  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const entryId = await joinWaitlist({
        request: {
          learnerAccountId: this.selectedLearnerId,
          offeringId: this.offeringId,
          priority: Number(this.priority),
          discountCode: this.discountCode || null,
          notes: this.notes || null
        }
      });
      this.close(entryId);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isSaving = false;
    }
  }
}
