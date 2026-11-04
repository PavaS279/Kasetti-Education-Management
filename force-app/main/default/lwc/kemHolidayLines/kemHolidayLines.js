import { LightningElement, api } from "lwc";

const TYPES = ["Public Holiday", "Term Break", "Branch Closure", "Other"].map(
  (v) => ({ label: v, value: v })
);

let holidayKey = 0;
const today = () => {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 10);
};

/** Holiday lines from the server's suggestions: past ones are left unticked. */
export function toHolidayLines(suggested) {
  const now = today();
  return (suggested || []).map((h) => ({
    key: `hol-${++holidayKey}`,
    include: (h.endDate || h.startDate) >= now,
    name: h.name,
    startDate: h.startDate,
    endDate: h.endDate,
    closureType: h.closureType || "Public Holiday",
    checkDate: Boolean(h.checkDate)
  }));
}

export function newHoliday() {
  return {
    key: `hol-${++holidayKey}`,
    include: true,
    name: "",
    startDate: undefined,
    endDate: undefined,
    closureType: "Public Holiday",
    checkDate: false
  };
}

/** What the server needs: the ticked lines with a name. */
export function holidayRequest(lines) {
  return (lines || [])
    .filter((l) => l.include && (l.name || "").trim())
    .map((l) => ({
      name: l.name.trim(),
      startDate: l.startDate,
      endDate: l.endDate || l.startDate,
      closureType: l.closureType
    }));
}

/** Editable list of holidays and breaks with a tick to include each. Fires "change" with the lines. */
export default class KemHolidayLines extends LightningElement {
  @api lines = [];
  typeOptions = TYPES;

  get rows() {
    const now = today();
    return (this.lines || []).map((l, index) => ({
      ...l,
      index,
      isPast: Boolean(l.startDate) && (l.endDate || l.startDate) < now,
      rowClass: l.include ? "holiday" : "holiday holiday_off"
    }));
  }

  get chosen() {
    return holidayRequest(this.lines).length;
  }

  get hasCheckDates() {
    return (this.lines || []).some((l) => l.checkDate && l.include);
  }

  emit(lines) {
    this.dispatchEvent(new CustomEvent("change", { detail: { lines } }));
  }

  handleField(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    let value;
    if (field === "include") {
      value = event.target.checked;
    } else if (event.detail?.value !== undefined) {
      value = event.detail.value;
    } else {
      value = event.target.value;
    }
    this.emit(
      this.lines.map((l, i) => {
        if (i !== index) {
          return l;
        }
        const next = { ...l, [field]: value };
        // A date someone has set is no longer a suggestion to check.
        if (field === "startDate" || field === "endDate") {
          next.checkDate = false;
          if (
            field === "startDate" &&
            (!l.endDate || l.endDate === l.startDate)
          ) {
            next.endDate = value;
          }
        }
        return next;
      })
    );
  }

  handleAdd() {
    this.emit([...this.lines, newHoliday()]);
  }

  handleRemove(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.emit(this.lines.filter((_, i) => i !== index));
  }

  @api
  reportValidity() {
    const inputs = [...this.template.querySelectorAll("lightning-input")];
    return inputs.reduce((ok, i) => i.reportValidity() && ok, true);
  }
}
