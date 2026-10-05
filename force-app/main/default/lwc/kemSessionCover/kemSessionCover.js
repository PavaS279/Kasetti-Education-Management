import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import SESSION from "@salesforce/schema/Class_Session__c";
import STATUS from "@salesforce/schema/Class_Session__c.Status__c";
import NEEDS_COVER from "@salesforce/schema/Class_Session__c.Needs_Cover__c";
import TEACHER from "@salesforce/schema/Class_Session__c.Teacher_User__r.Name";
import ORIGINAL_TEACHER from "@salesforce/schema/Class_Session__c.Original_Teacher__r.Name";
import ROOM from "@salesforce/schema/Class_Session__c.Room__r.Name";
import ORIGINAL_ROOM from "@salesforce/schema/Class_Session__c.Original_Room__r.Name";
import NOTE from "@salesforce/schema/Class_Session__c.Cover_Note__c";
import getCandidates from "@salesforce/apex/CoverController.getCandidates";
import getRoomOptions from "@salesforce/apex/CoverController.getRoomOptions";
import assignCover from "@salesforce/apex/CoverController.assignCover";
import swapRoom from "@salesforce/apex/CoverController.swapRoom";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const FIELDS = [
  STATUS,
  NEEDS_COVER,
  TEACHER,
  ORIGINAL_TEACHER,
  ROOM,
  ORIGINAL_ROOM,
  NOTE
];

/** Session teacher and room, with cover teacher and room swap suggestions. */
export default class KemSessionCover extends LightningElement {
  @api recordId;
  record;
  canArrange = false;
  mode;
  options = [];
  note = "";
  errorMessage;
  isBusy = false;

  @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
  wiredRecord({ data, error }) {
    if (data) {
      this.record = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  @wire(getObjectInfo, { objectApiName: SESSION })
  wiredInfo({ data }) {
    if (data) {
      this.canArrange =
        data.fields.Teacher_User__c?.updateable === true &&
        data.fields.Room__c?.updateable === true;
    }
  }

  value(field) {
    return getFieldValue(this.record, field);
  }
  get teacher() {
    return this.value(TEACHER) || "No teacher";
  }
  get originalTeacher() {
    return this.value(ORIGINAL_TEACHER);
  }
  get room() {
    return this.value(ROOM) || "No room";
  }
  get originalRoom() {
    return this.value(ORIGINAL_ROOM);
  }
  get coverNote() {
    return this.value(NOTE);
  }
  get needsCover() {
    return this.value(NEEDS_COVER) === true;
  }
  get scheduled() {
    return this.value(STATUS) === "Scheduled";
  }
  get showActions() {
    return this.canArrange && this.scheduled;
  }
  get coverLabel() {
    return this.needsCover ? "Find cover" : "Change teacher";
  }
  get pickingTeacher() {
    return this.mode === "teacher";
  }
  get pickingRoom() {
    return this.mode === "room";
  }
  get teacherOptions() {
    return this.options.map((c) => ({
      ...c,
      key: c.userId,
      className: `option${c.free ? "" : " option_busy"}`,
      detail: c.free
        ? [
            c.taughtCourse ? "has taught this course" : null,
            `${c.sessionsThatDay} other that day`
          ]
            .filter(Boolean)
            .join(" · ")
        : c.clash,
      disabled: !c.free || this.isBusy
    }));
  }
  get roomOptions() {
    return this.options.map((r) => ({
      ...r,
      key: r.roomId,
      className: `option${r.free && r.bigEnough ? "" : " option_busy"}`,
      detail: !r.free
        ? r.clash
        : !r.bigEnough
          ? `Holds ${r.capacity}: too small`
          : `${r.roomType || "Room"} · holds ${r.capacity}`,
      disabled: !r.free || !r.bigEnough || this.isBusy
    }));
  }
  get noOptions() {
    return this.mode && this.options.length === 0;
  }

  async openPicker(mode) {
    this.mode = mode;
    this.options = [];
    this.isBusy = true;
    try {
      this.options =
        mode === "teacher"
          ? await getCandidates({ sessionId: this.recordId })
          : await getRoomOptions({ sessionId: this.recordId });
    } catch (error) {
      toastError(this, error, "Could not load options");
      this.mode = undefined;
    } finally {
      this.isBusy = false;
    }
  }

  handleTeacherPicker() {
    this.openPicker("teacher");
  }
  handleRoomPicker() {
    this.openPicker("room");
  }
  handleClose() {
    this.mode = undefined;
  }
  handleNote(event) {
    this.note = event.target.value || "";
  }

  async apply(action, title, message) {
    this.isBusy = true;
    try {
      await action();
      toast(this, title, message);
      this.mode = undefined;
      this.note = "";
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      toastError(this, error, "Change not saved");
    } finally {
      this.isBusy = false;
    }
  }

  handleAssign(event) {
    const { id, name } = event.currentTarget.dataset;
    this.apply(
      () =>
        assignCover({
          sessionId: this.recordId,
          coverUserId: id,
          note: this.note || null
        }),
      "Teacher changed",
      `${name} is teaching this session.`
    );
  }

  handleMove(event) {
    const { id, name } = event.currentTarget.dataset;
    this.apply(
      () =>
        swapRoom({
          sessionId: this.recordId,
          roomId: id,
          note: this.note || null
        }),
      "Room changed",
      `The session is now in ${name}.`
    );
  }
}
