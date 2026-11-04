import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getContext from "@salesforce/apex/NewRouterController.getContext";
import BranchWizard from "c/kemBranchWizardModal";
import RoomModal from "c/kemRoomModal";
import CourseWizard from "c/kemCourseWizardModal";
import ClassWizard from "c/kemClassWizardModal";
import FamilyModal from "c/kemFamilyModal";
import { reduceErrors, toast } from "c/kemUtils";

/** The record a related-list New was pressed from ("1." + base64 JSON page reference). */
export function parentFrom(inContextOfRef) {
  if (!inContextOfRef) {
    return null;
  }
  try {
    const encoded = inContextOfRef.startsWith("1.")
      ? inContextOfRef.slice(2)
      : inContextOfRef;
    const ref = JSON.parse(atob(encoded));
    const attrs = ref?.attributes || {};
    return attrs.recordId
      ? { recordId: attrs.recordId, objectApiName: attrs.objectApiName }
      : null;
  } catch {
    return null;
  }
}

/** "Branch__c=a0M…,Name=X" → { Branch__c: "a0M…", Name: "X" } */
export function fieldValuesFrom(defaultFieldValues) {
  const values = {};
  (defaultFieldValues || "").split(",").forEach((pair) => {
    const at = pair.indexOf("=");
    if (at > 0) {
      values[pair.slice(0, at)] = decodeURIComponent(pair.slice(at + 1));
    }
  });
  return values;
}

/**
 * Behind the standard New button on Branch, Room, Course, Class and Account:
 * staff go straight to the guided screen, administrators choose between it
 * and the standard form; others get the standard form.
 */
export default class KemNewRouter extends NavigationMixin(LightningElement) {
  @api pageReference;
  context;
  showChoice = false;
  errorMessage;
  isLoading = true;

  get objectApiName() {
    return this.pageReference?.attributes?.objectApiName;
  }
  get state() {
    return this.pageReference?.state || {};
  }
  get parent() {
    return parentFrom(this.state.inContextOfRef);
  }
  get heading() {
    return `New ${this.context?.objectLabel || "record"}`;
  }

  async connectedCallback() {
    try {
      this.context = await getContext({
        objectApiName: this.objectApiName,
        recordTypeId: this.state.recordTypeId || null
      });
      if (!this.context.wizard) {
        this.openStandardForm();
      } else if (this.context.isAdministrator) {
        this.showChoice = true;
      } else {
        await this.openWizard();
      }
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  handleGuided() {
    this.showChoice = false;
    this.openWizard();
  }

  handleStandard() {
    this.openStandardForm();
  }

  handleCancel() {
    this.goBack();
  }

  /** The standard record form, bypassing this override. */
  openStandardForm() {
    const state = { nooverride: "1" };
    ["recordTypeId", "defaultFieldValues", "inContextOfRef"].forEach((k) => {
      if (this.state[k]) {
        state[k] = this.state[k];
      }
    });
    this[NavigationMixin.Navigate](
      {
        type: "standard__objectPage",
        attributes: { objectApiName: this.objectApiName, actionName: "new" },
        state
      },
      true
    );
  }

  parentIdOf(objectApiName) {
    const p = this.parent;
    return p && p.objectApiName === objectApiName ? p.recordId : undefined;
  }

  async openWizard() {
    const values = fieldValuesFrom(this.state.defaultFieldValues);
    let recordId;
    switch (this.context.wizard) {
      case "branch": {
        const r = await BranchWizard.open({
          size: "large",
          label: "New branch"
        });
        recordId = r?.branchId;
        break;
      }
      case "room": {
        const added = await RoomModal.open({
          size: "medium",
          label: "Add rooms",
          branchId: values.Branch__c || this.parentIdOf("Branch__c")
        });
        if (added) {
          toast(
            this,
            "Rooms added",
            `${added} room${added === 1 ? "" : "s"} added.`
          );
        }
        break;
      }
      case "course": {
        const r = await CourseWizard.open({
          size: "medium",
          label: "New course"
        });
        recordId = r?.courseId;
        if (r?.addClass) {
          const c = await ClassWizard.open({
            size: "medium",
            label: "New class",
            courseId: r.courseId
          });
          recordId = c?.classId || recordId;
        }
        break;
      }
      case "class": {
        const r = await ClassWizard.open({
          size: "medium",
          label: "New class",
          courseId:
            values.LearningCourseId || this.parentIdOf("LearningCourse"),
          branchId: values.Branch__c || this.parentIdOf("Branch__c")
        });
        recordId = r?.classId;
        break;
      }
      case "family": {
        const r = await FamilyModal.open({
          size: "large",
          label: "New family",
          branchId: values.Branch__c || this.parentIdOf("Branch__c")
        });
        recordId = r?.learnerIds?.[0];
        break;
      }
      default:
        break;
    }
    if (recordId) {
      this[NavigationMixin.Navigate](
        {
          type: "standard__recordPage",
          attributes: { recordId, actionName: "view" }
        },
        true
      );
    } else {
      this.goBack();
    }
  }

  /** Back to the record the button was pressed on, or the object's list. */
  goBack() {
    const p = this.parent;
    this[NavigationMixin.Navigate](
      p
        ? {
            type: "standard__recordPage",
            attributes: { recordId: p.recordId, actionName: "view" }
          }
        : {
            type: "standard__objectPage",
            attributes: {
              objectApiName: this.objectApiName,
              actionName: "list"
            },
            state: { filterName: "Recent" }
          },
      true
    );
  }
}
