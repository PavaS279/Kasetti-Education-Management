import { LightningElement, api } from "lwc";

const TYPES = ["Classroom", "Laboratory", "Hall", "Studio", "Virtual"].map(
  (v) => ({ label: v, value: v })
);

let roomKey = 0;
/** A blank room line. */
export function newRoom(name = "", roomType = "Classroom", capacity) {
  return {
    key: `room-${++roomKey}`,
    name,
    roomType,
    capacity,
    equipment: "",
    meetingUrl: ""
  };
}

/** Rows of rooms to add (name, type, seats, equipment, meeting link for virtual rooms). Fires "change" with the lines. */
export default class KemRoomLines extends LightningElement {
  @api lines = [];
  typeOptions = TYPES;

  get rows() {
    return (this.lines || []).map((l, index) => ({
      ...l,
      index,
      isVirtual: l.roomType === "Virtual",
      canRemove: this.lines.length > 1
    }));
  }

  get totalSeats() {
    return (this.lines || []).reduce(
      (sum, l) =>
        sum + (l.name && Number(l.capacity) > 0 ? Number(l.capacity) : 0),
      0
    );
  }

  get namedRooms() {
    return (this.lines || []).filter((l) => (l.name || "").trim()).length;
  }

  emit(lines) {
    this.dispatchEvent(new CustomEvent("change", { detail: { lines } }));
  }

  handleField(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.emit(
      this.lines.map((l, i) => {
        return i === index ? { ...l, [field]: value } : l;
      })
    );
  }

  handleAdd() {
    this.emit([...this.lines, newRoom()]);
  }

  handleRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.emit(this.lines.filter((_, i) => i !== index));
  }

  /** True when every named room has its seats (and a link if virtual). */
  @api
  reportValidity() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    return inputs.reduce((ok, i) => i.reportValidity() && ok, true);
  }
}
