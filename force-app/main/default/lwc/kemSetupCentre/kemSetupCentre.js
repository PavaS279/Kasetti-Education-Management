import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getCentre from "@salesforce/apex/SetupCentreController.getCentre";
import CourseWizard from "c/kemCourseWizardModal";
import ClassWizard from "c/kemClassWizardModal";
import FacultyModal from "c/kemFacultyModal";
import { reduceErrors, toast } from "c/kemUtils";

/**
 * Set-up Centre: counts, create buttons and set-up gaps for administrators,
 * branch managers and academic coordinators. Hidden for everyone else.
 * "New" opens a guided screen where one exists and the user can use it
 * (courses, classes, faculty), otherwise the standard record form.
 */
export default class KemSetupCentre extends NavigationMixin(LightningElement) {
  centre;
  errorMessage;
  hidden = false;
  isLoading = true;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.centre = await getCentre();
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    } finally {
      this.isLoading = false;
    }
  }

  get visible() {
    return !this.hidden;
  }

  get tiles() {
    return (this.centre?.tiles || []).map((t) => ({
      ...t,
      canList: Boolean(t.objectApiName || t.listRecordId)
    }));
  }

  get gapRows() {
    return (this.centre?.gaps || [])
      .filter((g) => g.count > 0)
      .map((g) => ({
        ...g,
        more: g.count > g.records.length ? g.count - g.records.length : 0
      }));
  }

  get hasGaps() {
    return this.gapRows.length > 0;
  }

  get gapBadgeLabel() {
    const n = this.centre?.openGaps || 0;
    return n ? `${n} to fix` : "All set";
  }

  get gapBadgeClass() {
    return this.centre?.openGaps
      ? "kem-badge kem-badge_warning"
      : "kem-badge kem-badge_success";
  }

  tileFor(key) {
    return (this.centre?.tiles || []).find((t) => t.key === key);
  }

  handleRefresh() {
    this.load();
  }

  async handleCreate(event) {
    const tile = this.tileFor(event.currentTarget.dataset.key);
    if (!tile.wizard) {
      this[NavigationMixin.Navigate]({
        type: "standard__objectPage",
        attributes: { objectApiName: tile.objectApiName, actionName: "new" }
      });
      return;
    }
    if (tile.key === "courses") {
      await this.newCourse();
    } else if (tile.key === "classes") {
      await this.newClass();
    } else if (tile.key === "faculty") {
      const id = await FacultyModal.open({
        size: "small",
        label: "New faculty member"
      });
      if (id) {
        toast(
          this,
          "Faculty member added",
          "Choose them as faculty on a class."
        );
        await this.load();
      }
    }
  }

  async newCourse() {
    const result = await CourseWizard.open({
      size: "medium",
      label: "New course"
    });
    if (!result?.courseId) {
      return;
    }
    toast(this, "Course created", "The course and its prices are ready.");
    if (result.addClass) {
      await this.newClass(result.courseId);
    } else {
      await this.load();
    }
  }

  async newClass(courseId) {
    const result = await ClassWizard.open({
      size: "medium",
      label: "New class",
      courseId
    });
    await this.load();
    if (result?.classId) {
      toast(
        this,
        "Class created",
        `${result.sessions} sessions added to the timetable.`
      );
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId: result.classId, actionName: "view" }
      });
    }
  }

  handleList(event) {
    const tile = this.tileFor(event.currentTarget.dataset.key);
    if (tile.listRecordId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: { recordId: tile.listRecordId, actionName: "view" }
      });
      return;
    }
    const pageRef = {
      type: "standard__objectPage",
      attributes: { objectApiName: tile.objectApiName, actionName: "list" }
    };
    if (tile.listView) {
      pageRef.state = { filterName: tile.listView };
    }
    this[NavigationMixin.Navigate](pageRef);
  }

  handleOpenRecord(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
}
