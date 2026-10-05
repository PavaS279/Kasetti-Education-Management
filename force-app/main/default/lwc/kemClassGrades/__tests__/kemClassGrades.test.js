import { createElement } from "lwc";
import KemClassGrades from "c/kemClassGrades";
import getClassGrades from "@salesforce/apex/GradingController.getClassGrades";
import saveWeights from "@salesforce/apex/GradingController.saveWeights";
import saveComments from "@salesforce/apex/GradingController.saveComments";
import finaliseGrades from "@salesforce/apex/GradingController.finaliseGrades";
import reopenGrades from "@salesforce/apex/GradingController.reopenGrades";
import LightningConfirm from "lightning/confirm";
import ReasonModal from "c/kemReasonModal";

jest.mock(
  "@salesforce/apex/GradingController.getClassGrades",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GradingController.saveWeights",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GradingController.saveComments",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GradingController.finaliseGrades",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/GradingController.reopenGrades",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemReasonModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function grades(overrides = {}) {
  return {
    className: "Chemistry",
    status: "Open",
    scale: "Standard",
    equalWeights: true,
    draftAssessments: 0,
    classAverage: 65.6,
    canEdit: true,
    canReopen: true,
    columns: [
      {
        assessmentId: "a01",
        name: "Final exam",
        assessmentType: "Exam",
        assessmentDate: "2026-10-01",
        weight: null,
        share: 50,
        published: true
      },
      {
        assessmentId: "a02",
        name: "Quiz 1",
        assessmentType: "Quiz",
        assessmentDate: "2026-10-03",
        weight: null,
        share: 50,
        published: true
      }
    ],
    rows: [
      {
        enrolmentId: "0x61",
        learnerName: "Asha Rao",
        score: 80,
        grade: "A",
        attendance: 100,
        comment: "Good work",
        cells: [
          { assessmentId: "a01", percent: 70, grade: "B", absent: false },
          { assessmentId: "a02", percent: 90, grade: "A+", absent: false }
        ]
      },
      {
        enrolmentId: "0x62",
        learnerName: "Bala Iyer",
        score: 25,
        grade: "F",
        attendance: null,
        reportCardId: "069A",
        cells: [
          { assessmentId: "a01", percent: 0, absent: true, grade: "ABS" },
          { assessmentId: "a02", percent: 50, grade: "D", absent: false }
        ]
      }
    ],
    ...overrides
  };
}

async function mount() {
  const el = createElement("c-kem-class-grades", { is: KemClassGrades });
  el.recordId = "0Of1";
  document.body.appendChild(el);
  await flush();
  return el;
}
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-class-grades", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows results, weights, scores and grades", async () => {
    getClassGrades.mockResolvedValue(grades());
    const el = await mount();
    const text = el.shadowRoot.textContent;
    expect(text).toContain("Asha Rao");
    expect(text).toContain("80.0%");
    expect(text).toContain("Absent");
    expect(text).toContain("50% of grade");
    expect(text).toContain("count equally");
    expect(el.shadowRoot.querySelector(".grade_top").textContent).toBe("A");
    expect(
      el.shadowRoot.querySelectorAll("lightning-input.weight")
    ).toHaveLength(2);
  });

  it("saves weights and comments", async () => {
    getClassGrades.mockResolvedValue(grades());
    saveWeights.mockResolvedValue(undefined);
    saveComments.mockResolvedValue(undefined);
    const el = await mount();
    const weight = el.shadowRoot.querySelector("lightning-input.weight");
    weight.value = "60";
    weight.dispatchEvent(new CustomEvent("change"));
    button(el, "Save weights").click();
    await flush();
    expect(saveWeights).toHaveBeenCalledWith({
      offeringId: "0Of1",
      weights: [
        { assessmentId: "a01", weight: 60 },
        { assessmentId: "a02", weight: null }
      ]
    });
    const comment = el.shadowRoot.querySelector("lightning-textarea");
    comment.value = "Revise reactions";
    comment.dispatchEvent(new CustomEvent("change"));
    button(el, "Save comments").click();
    await flush();
    expect(saveComments).toHaveBeenCalledWith({
      offeringId: "0Of1",
      comments: [{ enrolmentId: "0x61", comment: "Revise reactions" }]
    });
  });

  it("finalises after confirmation", async () => {
    getClassGrades.mockResolvedValue(grades());
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    finaliseGrades.mockResolvedValue(2);
    const el = await mount();
    button(el, "Finalise & issue report cards").click();
    await flush();
    await flush();
    expect(finaliseGrades).toHaveBeenCalledWith({ offeringId: "0Of1" });
  });

  it("locks final grades and reopens with a reason", async () => {
    getClassGrades.mockResolvedValue(
      grades({
        status: "Final",
        finalisedOn: "2026-10-05T10:00:00.000Z",
        finalisedBy: "Teacher"
      })
    );
    ReasonModal.open.mockResolvedValue("Exam re-marked");
    reopenGrades.mockResolvedValue(undefined);
    const el = await mount();
    expect(
      el.shadowRoot.querySelectorAll("lightning-input.weight")
    ).toHaveLength(0);
    expect(button(el, "Save weights")).toBeUndefined();
    expect(el.shadowRoot.querySelector("a.report")).toBeTruthy();
    button(el, "Reopen").click();
    await flush();
    await flush();
    expect(reopenGrades).toHaveBeenCalledWith({
      offeringId: "0Of1",
      reason: "Exam re-marked"
    });
  });

  it("warns about drafts and handles an empty class", async () => {
    getClassGrades.mockResolvedValue(grades({ draftAssessments: 1 }));
    let el = await mount();
    expect(el.shadowRoot.querySelector(".warning").textContent).toContain(
      "1 draft"
    );
    document.body.removeChild(el);
    getClassGrades.mockResolvedValue(grades({ columns: [], rows: [] }));
    el = await mount();
    expect(el.shadowRoot.textContent).toContain("No assessments yet");
  });
});
