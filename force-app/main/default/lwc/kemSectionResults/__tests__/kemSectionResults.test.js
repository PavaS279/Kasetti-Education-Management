import { createElement } from "lwc";
import KemSectionResults from "c/kemSectionResults";
import getSectionPanel from "@salesforce/apex/CollegeAcademicController.getSectionPanel";
import finaliseResults from "@salesforce/apex/CollegeAcademicController.finaliseResults";
import reopenResults from "@salesforce/apex/CollegeAcademicController.reopenResults";

jest.mock(
  "@salesforce/apex/CollegeAcademicController.getSectionPanel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.finaliseResults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAcademicController.reopenResults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);
const flush = () => new Promise((resolve) => process.nextTick(resolve));

const PANEL = {
  canFinalise: true,
  canReopen: true,
  subjects: [
    {
      id: "a0S1",
      subject: "Engineering Mathematics I",
      faculty: "Tara Teacher",
      term: 1,
      status: "Active",
      results: [
        {
          id: "a0R1",
          student: "Ravi",
          attempt: 1,
          internalMarks: 40,
          examMarks: 80,
          total: 120,
          max: 150,
          result: "Pass",
          status: "Final"
        }
      ]
    }
  ]
};

function mount() {
  const element = createElement("c-kem-section-results", {
    is: KemSectionResults
  });
  element.recordId = "0ZE000000000001";
  document.body.appendChild(element);
  return element;
}

describe("c-kem-section-results", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("lists subject results and finalises a subject", async () => {
    getSectionPanel.mockResolvedValue(PANEL);
    finaliseResults.mockResolvedValue(1);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(1);
    element.shadowRoot
      .querySelector('lightning-button[data-id="a0S1"]')
      .click();
    await flush();
    expect(finaliseResults).toHaveBeenCalledWith({ sectionSubjectId: "a0S1" });
    expect(getSectionPanel).toHaveBeenCalledTimes(2);
  });

  it("reopens a final result with a reason", async () => {
    getSectionPanel.mockResolvedValue(PANEL);
    reopenResults.mockResolvedValue();
    const element = mount();
    await flush();
    element.shadowRoot
      .querySelector('lightning-button[data-id="a0R1"]')
      .click();
    await flush();
    const reason = element.shadowRoot.querySelector(".reason lightning-input");
    reason.value = "Recount";
    reason.dispatchEvent(new CustomEvent("change"));
    byProp(
      element.shadowRoot,
      ".reason lightning-button",
      "label",
      "Reopen result"
    ).click();
    await flush();
    expect(reopenResults).toHaveBeenCalledWith({
      subjectResultIds: ["a0R1"],
      reason: "Recount"
    });
  });

  it("shows the error when loading fails", async () => {
    getSectionPanel.mockRejectedValue({ body: { message: "No access" } });
    const element = mount();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("No access");
  });
});
