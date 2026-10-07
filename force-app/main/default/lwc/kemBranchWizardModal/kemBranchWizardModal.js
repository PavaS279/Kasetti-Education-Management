import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import getSuggestedHolidays from "@salesforce/apex/SiteSetupController.getSuggestedHolidays";
import createBranch from "@salesforce/apex/SiteSetupController.createBranch";
import { newRoom } from "c/kemRoomLines";
import { toHolidayLines, holidayRequest } from "c/kemHolidayLines";
import { reduceErrors } from "c/kemUtils";

const STEPS = [
  { value: "branch", label: "Branch" },
  { value: "policies", label: "Policies" },
  { value: "rooms", label: "Rooms" },
  { value: "holidays", label: "Holidays" },
  { value: "review", label: "Check and open" }
];
const MODES = ["Classroom", "Online", "Hybrid"].map((v) => ({
  label: v,
  value: v
}));
const NONE = "";

/**
 * New branch: name, codes and manager; address and policies; rooms; the
 * year's holidays; then a summary before opening the branch (all or nothing).
 * Resolves to { branchId, rooms, holidays } or null.
 */
export default class KemBranchWizardModal extends LightningModal {
  steps = STEPS;
  step = "branch";
  modeOptions = MODES;
  managerOptions = [{ label: "Choose later", value: NONE }];
  yearOptions = [];
  year;

  form = {
    name: "",
    code: "",
    invoicePrefix: "",
    managerUserId: NONE,
    phone: "",
    email: "",
    street: "",
    city: "Bengaluru",
    state: "Karnataka",
    postalCode: "",
    country: "India",
    operatingHours: "Mon–Fri 15:00–20:00, Sat–Sun 09:00–18:00",
    deliveryModes: ["Classroom"],
    taxRate: 18,
    invoiceDueDays: 10,
    attendanceThreshold: 75,
    cancellationHours: 24
  };
  rooms = [newRoom("", "Classroom", 12)];
  holidays = [];
  prefixFromCode = false;

  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "New branch";
  }

  async connectedCallback() {
    try {
      const choices = await getChoices();
      this.managerOptions = [
        { label: "Choose later", value: NONE },
        ...(choices.managers || []).map((m) => ({
          label: m.label,
          value: m.value
        }))
      ];
      this.year = String(choices.year);
      this.yearOptions = [choices.year, choices.year + 1].map((y) => ({
        label: String(y),
        value: String(y)
      }));
      this.holidays = toHolidayLines(choices.suggestedHolidays);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  // ------------------------------------------------------------ steps

  get stepIndex() {
    return STEPS.findIndex((s) => s.value === this.step);
  }
  get isBranch() {
    return this.step === "branch";
  }
  get isPolicies() {
    return this.step === "policies";
  }
  get isRooms() {
    return this.step === "rooms";
  }
  get isHolidays() {
    return this.step === "holidays";
  }
  get isReview() {
    return this.step === "review";
  }
  get showBack() {
    return this.stepIndex > 0;
  }

  stepValid() {
    if (this.isRooms) {
      return this.template.querySelector("c-kem-room-lines").reportValidity();
    }
    if (this.isHolidays) {
      return this.template
        .querySelector("c-kem-holiday-lines")
        .reportValidity();
    }
    const inputs = [
      ...this.template.querySelectorAll(
        "lightning-input, lightning-combobox, lightning-checkbox-group"
      )
    ];
    return inputs.reduce((ok, i) => i.reportValidity() && ok, true);
  }

  handleNext() {
    this.errorMessage = undefined;
    if (!this.stepValid()) {
      return;
    }
    this.step = STEPS[this.stepIndex + 1].value;
  }

  handleBack() {
    this.errorMessage = undefined;
    this.step = STEPS[this.stepIndex - 1].value;
  }

  handleCancel() {
    this.close(null);
  }

  // ------------------------------------------------------------ fields

  handleField(event) {
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    const form = { ...this.form, [field]: value };
    // Suggest the invoice prefix from the code ("JPN-01" → "JPN").
    if (field === "code" && (!this.form.invoicePrefix || this.prefixFromCode)) {
      form.invoicePrefix = (value || "")
        .toUpperCase()
        .split("-")[0]
        .slice(0, 6);
      this.prefixFromCode = true;
    }
    if (field === "invoicePrefix") {
      this.prefixFromCode = false;
    }
    this.form = form;
  }

  handleRooms(event) {
    this.rooms = event.detail.lines;
  }

  handleHolidays(event) {
    this.holidays = event.detail.lines;
  }

  handleYear(event) {
    this.year = event.detail.value;
  }

  async handleSuggest() {
    this.isBusy = true;
    try {
      this.holidays = toHolidayLines(
        await getSuggestedHolidays({ year: Number(this.year) })
      );
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }

  // ------------------------------------------------------------ review and create

  get namedRooms() {
    return this.rooms.filter((l) => (l.name || "").trim());
  }
  get roomSummary() {
    const seats = this.namedRooms.reduce(
      (s, l) => s + (Number(l.capacity) || 0),
      0
    );
    return this.namedRooms.length
      ? `${this.namedRooms.length} rooms, ${seats} seats`
      : "None yet (add them later from the Set-up Centre)";
  }
  get holidaySummary() {
    const n = holidayRequest(this.holidays).length;
    return n ? `${n} holidays and breaks` : "None yet";
  }
  get managerName() {
    return (
      this.managerOptions.find((m) => m.value === this.form.managerUserId)
        ?.label || "Choose later"
    );
  }
  get modesText() {
    return (this.form.deliveryModes || []).join(", ");
  }
  get addressText() {
    const f = this.form;
    return [f.street, f.city, f.state, f.postalCode, f.country]
      .filter((v) => v && String(v).trim())
      .join(", ");
  }
  get noManager() {
    return !this.form.managerUserId;
  }

  get request() {
    const f = this.form;
    const num = (v) => {
      return v === "" || v === null || v === undefined ? null : Number(v);
    };
    return {
      name: f.name.trim(),
      code: f.code.trim(),
      invoicePrefix: f.invoicePrefix.trim(),
      managerUserId: f.managerUserId || null,
      phone: f.phone,
      email: f.email,
      street: f.street,
      city: f.city,
      state: f.state,
      postalCode: f.postalCode,
      country: f.country,
      operatingHours: f.operatingHours,
      deliveryModes: f.deliveryModes,
      taxRate: num(f.taxRate),
      invoiceDueDays: num(f.invoiceDueDays),
      attendanceThreshold: num(f.attendanceThreshold),
      cancellationHours: num(f.cancellationHours),
      rooms: this.namedRooms.map((l) => ({
        name: l.name.trim(),
        roomType: l.roomType,
        capacity: num(l.capacity),
        equipment: l.equipment,
        meetingUrl: l.meetingUrl
      })),
      holidays: holidayRequest(this.holidays)
    };
  }

  async handleCreate() {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await createBranch({ request: this.request });
      this.close({
        branchId: result.branchId,
        rooms: result.rooms,
        holidays: result.holidays
      });
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
