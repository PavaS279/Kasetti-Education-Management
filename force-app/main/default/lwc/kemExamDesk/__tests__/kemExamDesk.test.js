import { createElement } from "lwc";
import KemExamDesk from "c/kemExamDesk";
import LightningPrompt from "lightning/prompt";
import canSetUpExams from "@salesforce/apex/ExamController.canSetUpExams";
import getExams from "@salesforce/apex/ExamController.getExams";
import getExam from "@salesforce/apex/ExamController.getExam";
import registerCandidates from "@salesforce/apex/ExamController.registerCandidates";
import checkEligibility from "@salesforce/apex/ExamController.checkEligibility";
import overrideCandidate from "@salesforce/apex/ExamController.overrideCandidate";
import allocateSeats from "@salesforce/apex/ExamController.allocateSeats";
import issueTickets from "@salesforce/apex/ExamController.issueTickets";
import getMarkSheet from "@salesforce/apex/ExamController.getMarkSheet";
import saveMarks from "@salesforce/apex/ExamController.saveMarks";
import publishMarks from "@salesforce/apex/ExamController.publishMarks";

jest.mock(
  "@salesforce/apex/ExamController.canSetUpExams",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.getExams",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.getExam",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.registerCandidates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.checkEligibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.overrideCandidate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.allocateSeats",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.issueTickets",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.getMarkSheet",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.saveMarks",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ExamController.publishMarks",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => process.nextTick(resolve));
  }
};

const EXAMS = [
  { examId: "e1", name: "Term 1", code: "T1", status: "Scheduled" }
];
const DETAIL = {
  canManage: true,
  canOverride: true,
  exam: {
    examId: "e1",
    name: "Term 1",
    code: "T1",
    status: "Scheduled",
    examType: "Term",
    startDate: "2026-11-02",
    endDate: "2026-11-04",
    branch: "Central"
  },
  counts: { Registered: 0, Eligible: 1, Withheld: 1, "Ticket Issued": 0 },
  rooms: [
    { roomId: "r1", name: "Hall A", capacity: 20 },
    { roomId: "r2", name: "Room B", capacity: 10 }
  ],
  papers: [
    {
      paperId: "p1",
      name: "Paper 1",
      className: "Maths",
      paperDate: "2026-11-02",
      startTime: "09:30",
      maxMarks: 50,
      marksStatus: "Not Entered"
    }
  ],
  candidates: [
    {
      candidateId: "c1",
      hallTicket: "T1-0001",
      learner: "Asha",
      status: "Eligible",
      seat: "Hall A-01"
    },
    {
      candidateId: "c2",
      hallTicket: "T1-0002",
      learner: "Chitra",
      status: "Withheld",
      reason: "attendance 60.0% is below 80%"
    }
  ]
};
const SHEET = {
  editable: true,
  paper: {
    paperId: "p1",
    name: "Paper 1",
    className: "Maths",
    maxMarks: 50,
    marksStatus: "Draft"
  },
  rows: [
    {
      candidateId: "c1",
      hallTicket: "T1-0001",
      learner: "Asha",
      marks: null,
      absent: false
    },
    {
      candidateId: "c2",
      hallTicket: "T1-0002",
      learner: "Chitra",
      marks: null,
      absent: false
    }
  ]
};

async function mount() {
  const el = createElement("c-kem-exam-desk", { is: KemExamDesk });
  el.recordId = "b1";
  document.body.appendChild(el);
  await flush();
  return el;
}

function form(el, objectApiName) {
  return [...el.shadowRoot.querySelectorAll("lightning-record-edit-form")].find(
    (f) => f.objectApiName === objectApiName
  );
}

function button(el, label) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );
}

describe("c-kem-exam-desk", () => {
  beforeEach(() => {
    getExams.mockResolvedValue(EXAMS);
    getExam.mockResolvedValue(DETAIL);
    const step = { processed: 2, skipped: 1, notes: ["note"] };
    [registerCandidates, checkEligibility, allocateSeats, issueTickets].forEach(
      (m) => m.mockResolvedValue(step)
    );
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the exam with counts, papers and candidates", async () => {
    const el = await mount();
    expect(getExams).toHaveBeenCalledWith({ branchId: "b1" });
    expect(el.shadowRoot.textContent).toContain("02/11/2026 – 04/11/2026");
    const tiles = el.shadowRoot.querySelectorAll(".tile");
    expect(tiles).toHaveLength(5);
    expect(tiles[3].className).toContain("tile_warn");
    expect(el.shadowRoot.querySelectorAll(".kem-badge_danger")).toHaveLength(1);
    expect(el.shadowRoot.textContent).toContain("attendance 60.0%");
    expect(button(el, "Enter marks")).toBeDefined();
  });

  it("runs the steps with the chosen rooms", async () => {
    const el = await mount();
    button(el, "1. Register candidates").click();
    await flush();
    expect(registerCandidates).toHaveBeenCalledWith({ examId: "e1" });
    button(el, "2. Check eligibility").click();
    await flush();
    expect(checkEligibility).toHaveBeenCalled();
    el.shadowRoot
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["r2"] } }));
    button(el, "3. Allocate seats").click();
    await flush();
    expect(allocateSeats).toHaveBeenCalledWith({
      examId: "e1",
      roomIds: ["r2"]
    });
    button(el, "4. Issue hall tickets").click();
    await flush();
    expect(issueTickets).toHaveBeenCalledWith({ examId: "e1" });
  });

  it("allows a withheld candidate with a reason", async () => {
    LightningPrompt.open = jest.fn().mockResolvedValue("Medical certificate");
    overrideCandidate.mockResolvedValue();
    const el = await mount();
    button(el, "Allow").click();
    await flush();
    expect(overrideCandidate).toHaveBeenCalledWith({
      candidateId: "c2",
      reason: "Medical certificate"
    });
  });

  it("enters, saves and publishes marks", async () => {
    getMarkSheet.mockResolvedValue(SHEET);
    saveMarks.mockResolvedValue();
    publishMarks.mockResolvedValue("a1");
    const el = await mount();
    button(el, "Enter marks").click();
    await flush();
    const inputs = el.shadowRoot.querySelectorAll("lightning-input.mark-input");
    expect(inputs).toHaveLength(2);
    inputs[0].value = "45";
    inputs[0].dispatchEvent(new CustomEvent("change"));
    const absent = el.shadowRoot.querySelectorAll(
      'lightning-input[data-field="absent"]'
    )[1];
    absent.checked = true;
    absent.dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el, "Save marks").click();
    await flush();
    expect(saveMarks).toHaveBeenCalledWith({
      paperId: "p1",
      rows: [
        expect.objectContaining({
          candidateId: "c1",
          marks: 45,
          absent: false
        }),
        expect.objectContaining({ candidateId: "c2", absent: true })
      ]
    });
    button(el, "Publish to gradebook").click();
    await flush();
    expect(publishMarks).toHaveBeenCalledWith({ paperId: "p1" });
  });

  it("shows an empty state and hides without access", async () => {
    getExams.mockResolvedValue([]);
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("No exams yet");
    document.body.removeChild(el);
    getExams.mockRejectedValue({
      body: { message: "You do not have access to the Apex class" }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });

  it("creates an exam and its papers with record forms", async () => {
    const el = await mount();
    expect(button(el, "New exam")).toBeUndefined();
    canSetUpExams.emit(true);
    await flush();
    button(el, "New exam").click();
    await flush();
    const examForm = form(el, "Exam__c");
    expect(examForm).toBeDefined();
    examForm.dispatchEvent(
      new CustomEvent("success", { detail: { id: "e2" } })
    );
    await flush();
    expect(getExam).toHaveBeenLastCalledWith({ examId: "e2" });
    const paperForm = form(el, "Exam_Paper__c");
    expect(paperForm).toBeDefined();
    paperForm.dispatchEvent(
      new CustomEvent("success", { detail: { id: "p9" } })
    );
    await flush();
    expect(form(el, "Exam_Paper__c")).toBeUndefined();
  });
});
