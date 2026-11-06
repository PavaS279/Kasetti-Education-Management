import { createElement } from "lwc";
import KemCollegeSetup, { seatsFor, percentOf } from "c/kemCollegeSetup";
import getSetup from "@salesforce/apex/CollegeSetupController.getSetup";
import saveIntake from "@salesforce/apex/CollegeSetupController.saveIntake";
import saveRule from "@salesforce/apex/CollegeSetupController.saveRule";

jest.mock(
  "@salesforce/apex/CollegeSetupController.getSetup",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeSetupController.saveIntake",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeSetupController.saveRule",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function setup(canEdit) {
  return {
    canEdit,
    rows: [
      {
        id: "a0C1",
        campus: "Yelahanka Campus",
        branch: "BE Computer Science and Engineering",
        academicYear: "2026-27",
        intakeRegular: 60,
        intakeLateral: 6,
        usedRegular: 2,
        usedLateral: 0,
        admissionsOpen: true,
        deanExceptionsAllowed: true,
        regularRule: {
          ruleId: "a0R1",
          version: 1,
          qualifyingLevel: "PUC",
          minPercentage: 90,
          entranceRequired: true,
          entrances: [{ id: "a0E1", exam: "KCET", maxRank: 20000 }]
        }
      }
    ],
    history: [
      {
        changedOn: "2026-11-06T10:00:00.000Z",
        changedBy: "Kasetti Tech",
        what: "Regular seats · CB-0001",
        fromValue: "50",
        toValue: "60"
      }
    ]
  };
}

function mount() {
  const element = createElement("c-kem-college-setup", { is: KemCollegeSetup });
  document.body.appendChild(element);
  return element;
}

const button = (root, label) =>
  [...root.querySelectorAll("lightning-button")].find((b) => b.label === label);
const tab = (root, value) =>
  root.querySelector(`button[data-value="${value}"]`);

describe("c-kem-college-setup", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("is view-only for college staff", async () => {
    getSetup.mockResolvedValue(setup(false));
    const element = mount();
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("View only");
    expect(text).toContain(
      "Yelahanka Campus · BE Computer Science and Engineering"
    );
    expect(button(element.shadowRoot, "Edit")).toBeUndefined();
  });

  it("lets a System Administrator change the seats", async () => {
    getSetup.mockResolvedValue(setup(true));
    saveIntake.mockResolvedValue(setup(true));
    const element = mount();
    await flush();
    button(element.shadowRoot, "Edit").click();
    await flush();
    const regular = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((i) => i.label === "Regular seats");
    regular.value = "64";
    regular.dispatchEvent(new CustomEvent("change"));
    regular.reportValidity = () => true;
    element.shadowRoot
      .querySelectorAll("lightning-input")
      .forEach((i) => (i.reportValidity = () => true));
    button(element.shadowRoot, "Save").click();
    await flush();
    expect(saveIntake).toHaveBeenCalledWith({
      change: expect.objectContaining({ id: "a0C1", intakeRegular: 64 })
    });
  });

  it("saves an eligibility change as a new version", async () => {
    getSetup.mockResolvedValue(setup(true));
    saveRule.mockResolvedValue(setup(true));
    const element = mount();
    await flush();
    tab(element.shadowRoot, "rules").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain("KCET up to rank 20000");
    button(element.shadowRoot, "Edit").click();
    await flush();
    element.shadowRoot
      .querySelectorAll("lightning-input")
      .forEach((i) => (i.reportValidity = () => true));
    button(element.shadowRoot, "Save new version").click();
    await flush();
    expect(saveRule).toHaveBeenCalledWith({
      change: {
        ruleId: "a0R1",
        minPercentage: 90,
        entrances: [{ exam: "KCET", maxRank: 20000 }]
      }
    });
  });

  it("links the lateral percentage and seats", async () => {
    expect(seatsFor(60, 10)).toBe(6);
    expect(percentOf(60, 6)).toBe(10);
    expect(percentOf(0, 6)).toBeNull();
    getSetup.mockResolvedValue(setup(true));
    saveIntake.mockResolvedValue(setup(true));
    const element = mount();
    await flush();
    button(element.shadowRoot, "Edit").click();
    await flush();
    const pct = element.shadowRoot.querySelector(
      "lightning-input.lateral-percent"
    );
    pct.value = "15";
    pct.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-input.lateral-seats").value
    ).toBe(9);
    const seats = element.shadowRoot.querySelector(
      "lightning-input.lateral-seats"
    );
    seats.value = "12";
    seats.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-input.lateral-percent").value
    ).toBe(20);
  });

  it("shows the change history", async () => {
    getSetup.mockResolvedValue(setup(false));
    const element = mount();
    await flush();
    tab(element.shadowRoot, "history").click();
    await flush();
    expect(element.shadowRoot.textContent).toContain("50 → 60");
  });
});
