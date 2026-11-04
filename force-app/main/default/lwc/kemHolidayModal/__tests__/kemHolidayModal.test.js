import { createElement } from "lwc";
import KemHolidayModal from "c/kemHolidayModal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import getSuggestedHolidays from "@salesforce/apex/SiteSetupController.getSuggestedHolidays";
import addHolidays from "@salesforce/apex/SiteSetupController.addHolidays";

jest.mock(
  "@salesforce/apex/SiteSetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SiteSetupController.getSuggestedHolidays",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SiteSetupController.addHolidays",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const A = "a0M000000000001";
const B = "a0M000000000002";

describe("c-kem-holiday-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("suggests the year's list, leaves past dates unticked and adds to every chosen branch", async () => {
    getChoices.mockResolvedValue({
      year: 2026,
      branches: [
        { label: "Indiranagar", value: A },
        { label: "Koramangala", value: B }
      ]
    });
    getSuggestedHolidays.mockResolvedValue([
      {
        name: "Republic Day",
        startDate: "2000-01-26",
        endDate: "2000-01-26",
        closureType: "Public Holiday",
        checkDate: false
      },
      {
        name: "Deepavali break",
        startDate: "2099-11-07",
        endDate: "2099-11-10",
        closureType: "Term Break",
        checkDate: true
      }
    ]);
    addHolidays.mockResolvedValue({ created: 2, skipped: 0 });
    const element = createElement("c-kem-holiday-modal", {
      is: KemHolidayModal
    });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const button = (label) =>
      [...element.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === label || (b.label || "").startsWith(label)
      );
    // Both branches are chosen by default; the empty starting line counts for nothing.
    expect(button("Add 0 to 2 branches").disabled).toBe(true);
    button("Suggest the year's holidays").click();
    await settle();
    expect(getSuggestedHolidays).toHaveBeenCalledWith({ year: 2026 });
    const lines = element.shadowRoot.querySelector(
      "c-kem-holiday-lines"
    ).shadowRoot;
    expect(lines.textContent).toContain("Check date");
    expect(lines.textContent).toContain("Past");
    expect(lines.textContent).toContain("1 chosen");
    lines.querySelectorAll("lightning-input").forEach((i) => {
      i.reportValidity = () => true;
    });
    button("Add 1 to 2 branches").click();
    await settle();
    expect(addHolidays).toHaveBeenCalledWith({
      branchIds: [A, B],
      holidays: [
        {
          name: "Deepavali break",
          startDate: "2099-11-07",
          endDate: "2099-11-10",
          closureType: "Term Break"
        }
      ]
    });
    expect(closed.mock.calls[0][0].detail).toEqual({ created: 2, skipped: 0 });
  });

  it("starts from the given branch and adds a one-off closure", async () => {
    getChoices.mockResolvedValue({
      year: 2026,
      branches: [
        { label: "Indiranagar", value: A },
        { label: "Koramangala", value: B }
      ]
    });
    addHolidays.mockRejectedValue({
      body: { message: "Founders Day cannot end before it starts." }
    });
    const element = createElement("c-kem-holiday-modal", {
      is: KemHolidayModal
    });
    element.branchId = B;
    document.body.appendChild(element);
    await settle();
    const lines = element.shadowRoot.querySelector(
      "c-kem-holiday-lines"
    ).shadowRoot;
    const set = (field, value) => {
      const el = lines.querySelector(`[data-field="${field}"]`);
      el.value = value;
      el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
    };
    set("name", "Founders Day");
    await settle();
    set("startDate", "2099-12-01");
    await settle();
    // The end date follows the first day.
    expect(lines.querySelector('[data-field="endDate"]').value).toBe(
      "2099-12-01"
    );
    lines.querySelectorAll("lightning-input").forEach((i) => {
      i.reportValidity = () => true;
    });
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Add 1 to 1 branch")
      .click();
    await settle();
    expect(addHolidays.mock.calls[0][0].branchIds).toEqual([B]);
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("cannot end before");
  });
});
