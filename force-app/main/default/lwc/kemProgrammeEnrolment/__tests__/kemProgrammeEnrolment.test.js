import { createElement } from "lwc";
import KemProgrammeEnrolment from "c/kemProgrammeEnrolment";
import getEnrolmentPanel from "@salesforce/apex/CollegeAcademicController.getEnrolmentPanel";
import joinSection from "@salesforce/apex/CollegeAcademicController.joinSection";
import promote from "@salesforce/apex/CollegeAcademicController.promote";

jest.mock(
  "@salesforce/apex/CollegeAcademicController.getEnrolmentPanel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.joinSection",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.promote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.repeatYear",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.discontinue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.completeProgramme",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);
const flush = () => new Promise((resolve) => process.nextTick(resolve));

function panel(currentSection) {
  return {
    enrolment: {
      Id: "a0P1",
      Status__c: "Enrolled",
      Roll_Number__c: "KT26YBCS001",
      Current_Year_Of_Study__c: 1,
      Student__r: { Name: "Ravi Kumar" },
      Programme__r: { Name: "BE" },
      Branch__r: { Name: "CSE" },
      Campus__r: { Name: "Yelahanka Campus" }
    },
    currentSection,
    sectionsThisYear: [{ label: "Y1 A", value: "0ZE1" }],
    sectionsNextYear: [{ label: "Y2 A", value: "0ZE2" }],
    subjects: [
      {
        id: "a0R1",
        subject: "Engineering Mathematics I",
        term: 1,
        attempt: 1,
        attendancePercent: 92.5,
        result: "Pass",
        status: "Final"
      }
    ],
    terms: [],
    openBacklogs: 0,
    canAct: true
  };
}

function mount() {
  const element = createElement("c-kem-programme-enrolment", {
    is: KemProgrammeEnrolment
  });
  element.recordId = "a0P1";
  document.body.appendChild(element);
  return element;
}

describe("c-kem-programme-enrolment", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("joins a section with the joining date", async () => {
    getEnrolmentPanel.mockResolvedValue(panel(null));
    joinSection.mockResolvedValue("0ZP1");
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector("h2").textContent).toContain(
      "KT26YBCS001"
    );
    expect(element.shadowRoot.querySelector("tbody").textContent).toContain(
      "92.5%"
    );
    const combo = element.shadowRoot.querySelector("lightning-combobox");
    combo.dispatchEvent(
      new CustomEvent("change", { detail: { value: "0ZE1" } })
    );
    const date = byProp(element.shadowRoot, "lightning-input", "type", "date");
    date.value = "2026-08-01";
    date.dispatchEvent(new CustomEvent("change"));
    byProp(
      element.shadowRoot,
      "lightning-button",
      "label",
      "Join section"
    ).click();
    await flush();
    expect(joinSection).toHaveBeenCalledWith({
      programmeEnrolmentId: "a0P1",
      sectionId: "0ZE1",
      joiningDate: "2026-08-01"
    });
  });

  it("promotes a joined student into a next-year section", async () => {
    getEnrolmentPanel.mockResolvedValue(panel("Y1 A"));
    promote.mockResolvedValue("0ZP2");
    const element = mount();
    await flush();
    const combo = element.shadowRoot.querySelector("lightning-combobox");
    expect(combo.options[0].value).toBe("0ZE2");
    combo.dispatchEvent(
      new CustomEvent("change", { detail: { value: "0ZE2" } })
    );
    byProp(element.shadowRoot, "lightning-button", "label", "Promote").click();
    await flush();
    expect(promote).toHaveBeenCalledWith({
      programmeEnrolmentId: "a0P1",
      sectionId: "0ZE2"
    });
  });

  it("hides the Dean actions from other users", async () => {
    getEnrolmentPanel.mockResolvedValue({ ...panel("Y1 A"), canAct: false });
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector(".actions")).toBeNull();
  });
});
