import { api } from "lwc";
import LightningModal from "lightning/modal";
import addSession from "@salesforce/apex/TimetableController.addSession";
import { reduceErrors } from "c/kemUtils";

const TYPES = ["Make-up", "Extra", "Class", "Lab", "Exam"].map((v) => ({
  label: v,
  value: v
}));
const LENGTHS = [30, 45, 60, 90, 120, 180].map((m) => ({
  label:
    m < 60 || m % 60 ? `${m} minutes` : `${m / 60} hour${m > 60 ? "s" : ""}`,
  value: String(m)
}));

const pad = (n) => String(n).padStart(2, "0");

/**
 * Adds one session to a class outside its weekly pattern (a make-up or extra
 * session). The class's teacher and room are used; a clash is refused with
 * the reason. Resolves to the new session Id, or null.
 */
export default class KemSessionModal extends LightningModal {
  @api offeringId;
  @api offeringName;
  typeOptions = TYPES;
  lengthOptions = LENGTHS;
  sessionType = "Make-up";
  minutes = "60";
  day;
  startTime;
  errorMessage;
  isBusy = false;

  connectedCallback() {
    // Default: the next quarter hour today.
    const now = new Date();
    now.setMinutes(Math.ceil(now.getMinutes() / 15) * 15, 0, 0);
    this.day = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
    this.startTime = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
  }

  get heading() {
    return this.offeringName
      ? `Add a session · ${this.offeringName}`
      : "Add a session";
  }
  get timeValue() {
    return `${this.startTime}:00.000`;
  }
  get cannotSave() {
    return this.isBusy || !this.day || !this.startTime;
  }

  handleType(event) {
    this.sessionType = event.detail.value;
  }
  handleDay(event) {
    this.day = event.target.value;
  }
  handleTime(event) {
    this.startTime = (event.target.value || "").slice(0, 5);
  }
  handleLength(event) {
    this.minutes = event.detail.value;
  }
  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    this.isBusy = true;
    this.errorMessage = undefined;
    const [y, m, d] = this.day.split("-").map(Number);
    const [h, min] = this.startTime.split(":").map(Number);
    const start = new Date(y, m - 1, d, h, min, 0, 0);
    const end = new Date(start.getTime() + Number(this.minutes) * 60000);
    try {
      const id = await addSession({
        offeringId: this.offeringId,
        startAt: start.toISOString(),
        endAt: end.toISOString(),
        sessionType: this.sessionType,
        roomId: null
      });
      this.close(id);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
