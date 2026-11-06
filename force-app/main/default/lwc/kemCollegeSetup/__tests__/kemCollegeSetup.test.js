import { createElement } from "lwc";
import KemCollegeSetup, {
  seatsFor,
  percentOf,
  previousYear
} from "c/kemCollegeSetup";
import getSetup from "@salesforce/apex/CollegeSetupController.getSetup";
import saveIntake from "@salesforce/apex/CollegeSetupController.saveIntake";
import saveRule from "@salesforce/apex/CollegeSetupController.saveRule";
import getFees from "@salesforce/apex/CollegeSetupController.getFees";
import saveFees from "@salesforce/apex/CollegeSetupController.saveFees";

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
jest.mock(
  "@salesforce/apex/CollegeSetupController.saveQuota",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeSetupController.saveSplit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeSetupController.getFees",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeSetupController.saveFees",
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
        courseId: "0lC1",
        split: [],
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

  it("edits fees by quota and copies the CET amounts", async () => {
    expect(previousYear("2026-27")).toBe("2025-26");
    const grid = {
      quotas: [{ name: "Default (CET)" }, { id: "a0Q2", name: "Management" }],
      rows: [
        {
          feeType: "Tuition",
          frequency: "Annual",
          cells: [
            { quotaId: null, amount: 150000 },
            { quotaId: "a0Q2", amount: null, fallback: 150000 }
          ]
        }
      ]
    };
    getSetup.mockResolvedValue(setup(true));
    getFees.mockResolvedValue(grid);
    saveFees.mockResolvedValue(grid);
    const element = mount();
    await flush();
    tab(element.shadowRoot, "fees").click();
    await flush();
    expect(getFees).toHaveBeenCalledWith({
      courseId: "0lC1",
      academicYear: "2026-27",
      yearOfStudy: null
    });
    expect(element.shadowRoot.textContent).toContain("uses 150000");
    button(element.shadowRoot, "Edit fees").click();
    await flush();
    button(element.shadowRoot, "Copy from CET").click();
    await flush();
    element.shadowRoot
      .querySelectorAll("lightning-input")
      .forEach((i) => (i.reportValidity = () => true));
    button(element.shadowRoot, "Save fees").click();
    await flush();
    const sent = saveFees.mock.calls[0][0].request;
    expect(sent.rows[0].cells).toEqual([
      { quotaId: null, amount: 150000 },
      { quotaId: "a0Q2", amount: 150000 }
    ]);
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
