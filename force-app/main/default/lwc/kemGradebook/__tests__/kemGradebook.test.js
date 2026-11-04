import { createElement } from "lwc";
import KemGradebook, { gradeFor } from "c/kemGradebook";
import LightningConfirm from "lightning/confirm";
import getGradebook from "@salesforce/apex/AssessmentController.getGradebook";
import saveResults from "@salesforce/apex/AssessmentController.saveResults";
import publish from "@salesforce/apex/AssessmentController.publish";

jest.mock(
  "@salesforce/apex/AssessmentController.getGradebook",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AssessmentController.saveResults",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AssessmentController.publish",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/confirm",
  () => ({
    __esModule: true,
    default: { open: jest.fn(() => Promise.resolve(true)) }
  }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const BANDS = [
  { grade: "A+", minPercent: 90 },
  { grade: "A", minPercent: 80 },
  { grade: "B", minPercent: 70 },
  { grade: "C", minPercent: 60 },
  { grade: "D", minPercent: 50 },
  { grade: "F", minPercent: 0 }
];

function book(overrides = {}) {
  return {
    canEdit: true,
    bands: BANDS,
    assessment: {
      Id: "a0Q000000000001",
      Name: "Unit test 1",
      Assessment_Type__c: "Test",
      Max_Score__c: 50,
      Status__c: "Draft",
      Course_Offering__r: { Name: "Maths Sat AM" }
    },
    rows: [
      {
        learnerContactId: "003000000000001",
        enrolmentId: "0kX000000000001",
        learnerName: "Ananya Sharma",
        score: 47,
        absent: false
      },
      {
        learnerContactId: "003000000000002",
        enrolmentId: "0kX000000000002",
        learnerName: "Arjun Sharma",
        score: null,
        absent: false
      }
    ],
    ...overrides
  };
}

async function mount() {
  const element = createElement("c-kem-gradebook", { is: KemGradebook });
  element.recordId = "a0Q000000000001";
  document.body.appendChild(element);
  await flush();
  // Base-component stubs have no validity API.
  element.shadowRoot
    .querySelectorAll("lightning-input.score")
    .forEach((input) => {
      input.reportValidity = () => true;
    });
  return element;
}

const button = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-gradebook", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("maps percentages to grade bands", () => {
    expect(gradeFor(94, BANDS)).toBe("A+");
    expect(gradeFor(62, BANDS)).toBe("C");
    expect(gradeFor(0, BANDS)).toBe("F");
    expect(gradeFor(null, BANDS)).toBeNull();
  });

  it("previews grades live and saves a draft", async () => {
    getGradebook.mockResolvedValue(book());
    saveResults.mockResolvedValue(undefined);
    const element = await mount();
    const grades = () =>
      [...element.shadowRoot.querySelectorAll(".grade")].map(
        (g) => g.textContent
      );
    expect(grades()).toEqual(["A+", "—"]);

    const score = element.shadowRoot.querySelector(
      'lightning-input.score[data-id="003000000000002"]'
    );
    score.value = 31;
    score.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(grades()).toEqual(["A+", "C"]);

    const absent = element.shadowRoot.querySelector(
      'lightning-input.absent[data-id="003000000000001"]'
    );
    absent.checked = true;
    absent.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(grades()).toEqual(["ABS", "C"]);

    button(element, "Save draft").click();
    await flush();
    expect(saveResults).toHaveBeenCalledWith({
      assessmentId: "a0Q000000000001",
      rows: [
        expect.objectContaining({
          learnerContactId: "003000000000001",
          absent: true,
          score: null
        }),
        expect.objectContaining({
          learnerContactId: "003000000000002",
          score: 31,
          absent: false
        })
      ]
    });
  });

  it("publishes after confirmation", async () => {
    getGradebook.mockResolvedValue(book());
    publish.mockResolvedValue(undefined);
    const element = await mount();
    button(element, "Publish results").click();
    await flush();
    await flush();
    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(publish).toHaveBeenCalledWith({ assessmentId: "a0Q000000000001" });
    expect(saveResults).not.toHaveBeenCalled();
  });

  it("is read-only once published", async () => {
    const published = book({ canEdit: false });
    published.assessment.Status__c = "Published";
    published.rows[0].grade = "A+";
    getGradebook.mockResolvedValue(published);
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("published and locked");
    expect(button(element, "Publish results")).toBeUndefined();
  });

  it("shows load errors", async () => {
    getGradebook.mockRejectedValue({ body: { message: "No access" } });
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("No access");
  });
});
