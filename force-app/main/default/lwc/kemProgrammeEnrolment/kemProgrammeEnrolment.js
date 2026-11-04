import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getEnrolmentPanel from "@salesforce/apex/CollegeAcademicController.getEnrolmentPanel";
import joinSection from "@salesforce/apex/CollegeAcademicController.joinSection";
import promote from "@salesforce/apex/CollegeAcademicController.promote";
import repeatYear from "@salesforce/apex/CollegeAcademicController.repeatYear";
import discontinue from "@salesforce/apex/CollegeAcademicController.discontinue";
import completeProgramme from "@salesforce/apex/CollegeAcademicController.completeProgramme";

/** Programme enrolment page: joining, promotion, repeat, discontinue, completion, subject results and attendance. */
export default class KemProgrammeEnrolment extends LightningElement {
  @api recordId;
  enrolment;
  currentSection;
  sectionsThisYear = [];
  sectionsNextYear = [];
  subjects = [];
  terms = [];
  openBacklogs = 0;
  canAct = false;
  sectionId;
  joiningDate;
  reason = "";
  errorMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      const panel = await getEnrolmentPanel({
        programmeEnrolmentId: this.recordId
      });
      this.enrolment = panel.enrolment;
      this.currentSection = panel.currentSection;
      this.sectionsThisYear = panel.sectionsThisYear || [];
      this.sectionsNextYear = panel.sectionsNextYear || [];
      this.terms = panel.terms || [];
      this.openBacklogs = panel.openBacklogs;
      this.canAct = panel.canAct;
      this.subjects = (panel.subjects || []).map((r) => ({
        ...r,
        attendanceLabel:
          r.attendancePercent === null || r.attendancePercent === undefined
            ? "—"
            : `${r.attendancePercent}%`
      }));
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "The programme enrolment could not be loaded.";
    }
  }

  get rollNumber() {
    return this.enrolment?.Roll_Number__c || "no roll number yet";
  }

  get sectionLabel() {
    return this.currentSection || "not joined";
  }

  get joiningLabel() {
    return this.enrolment?.Joining_Date__c || "—";
  }

  get notJoined() {
    return !this.currentSection;
  }

  get showActions() {
    return this.canAct && this.enrolment?.Status__c === "Enrolled";
  }

  get sectionOptions() {
    return this.notJoined
      ? this.sectionsThisYear
      : [...this.sectionsNextYear, ...this.sectionsThisYear];
  }

  handleSection(event) {
    this.sectionId = event.detail.value;
  }

  handleJoiningDate(event) {
    this.joiningDate = event.target.value;
  }

  handleReason(event) {
    this.reason = event.target.value;
  }

  handleJoin() {
    return this.run(
      () =>
        joinSection({
          programmeEnrolmentId: this.recordId,
          sectionId: this.sectionId,
          joiningDate: this.joiningDate
        }),
      "Student joined the section"
    );
  }

  handlePromote() {
    return this.run(
      () =>
        promote({
          programmeEnrolmentId: this.recordId,
          sectionId: this.sectionId
        }),
      "Promoted to the next year"
    );
  }

  handleRepeat() {
    return this.run(
      () =>
        repeatYear({
          programmeEnrolmentId: this.recordId,
          sectionId: this.sectionId,
          reason: this.reason
        }),
      "Repeating the year"
    );
  }

  handleComplete() {
    return this.run(
      () => completeProgramme({ programmeEnrolmentId: this.recordId }),
      "Programme completed"
    );
  }

  handleDiscontinue() {
    return this.run(
      () =>
        discontinue({
          programmeEnrolmentId: this.recordId,
          reason: this.reason
        }),
      "Student discontinued"
    );
  }

  async run(action, success) {
    try {
      await action();
      this.dispatchEvent(
        new ShowToastEvent({ title: success, variant: "success" })
      );
      await this.load();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Not saved",
          message: error?.body?.message,
          variant: "error"
        })
      );
    }
  }
}
