import { createElement } from "lwc";
import KemCoverDesk from "c/kemCoverDesk";
import getDesk from "@salesforce/apex/CoverController.getDesk";
import assignCover from "@salesforce/apex/CoverController.assignCover";
import cancelForAbsence from "@salesforce/apex/CoverController.cancelForAbsence";
import withdrawAbsence from "@salesforce/apex/CoverController.withdrawAbsence";
import AbsenceModal from "c/kemAbsenceModal";
import ReasonModal from "c/kemReasonModal";

jest.mock(
  "@salesforce/apex/CoverController.getDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.assignCover",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.cancelForAbsence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.withdrawAbsence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemAbsenceModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "c/kemReasonModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const DESK = {
  canArrange: true,
  currentUserId: "005A",
  teachers: [{ Id: "005B", Name: "Bina" }],
  absences: [
    {
      Id: "a0S1",
      Staff_User__c: "005A",
      Staff_User__r: { Name: "Arun" },
      Reason__c: "Sick Leave",
      Status__c: "Partially Covered",
      Start__c: "2026-10-07T00:00:00.000Z",
      End__c: "2026-10-08T18:00:00.000Z",
      Sessions_Affected__c: 2,
      Sessions_Handled__c: 1
    }
  ],
  uncovered: [
    {
      learners: 12,
      session: {
        Id: "a0X1",
        Start__c: "2026-10-08T10:00:00.000Z",
        End__c: "2026-10-08T11:00:00.000Z",
        Course_Offering__r: { Name: "Maths Foundation" },
        Room__r: { Name: "R1" },
        Teacher_User__r: { Name: "Arun" }
      },
      candidates: [
        {
          userId: "005B",
          name: "Bina",
          free: true,
          taughtCourse: true,
          sessionsThatDay: 1
        },
        {
          userId: "005C",
          name: "Chetan",
          free: false,
          taughtCourse: false,
          sessionsThatDay: 3,
          clash: "Teaching Art Club"
        }
      ]
    }
  ]
};

async function mount() {
  const element = createElement("c-kem-cover-desk", { is: KemCoverDesk });
  document.body.appendChild(element);
  await flush();
  return element;
}
const buttons = (el) => [...el.shadowRoot.querySelectorAll("lightning-button")];

describe("c-kem-cover-desk", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("lists sessions needing cover with ranked teachers and absences", async () => {
    getDesk.mockResolvedValue(DESK);
    const el = await mount();
    const text = el.shadowRoot.textContent;
    expect(text).toContain("Maths Foundation");
    expect(text).toContain("has taught this course");
    expect(text).toContain("Teaching Art Club");
    expect(text).toContain("1 of 2 sessions handled");
    const assign = buttons(el).filter((b) => b.label === "Assign");
    expect(assign[0].disabled).toBe(false);
    expect(assign[1].disabled).toBe(true);
  });

  it("assigns cover, cancels a session and withdraws an absence", async () => {
    getDesk.mockResolvedValue(DESK);
    assignCover.mockResolvedValue(undefined);
    cancelForAbsence.mockResolvedValue(undefined);
    withdrawAbsence.mockResolvedValue(undefined);
    ReasonModal.open.mockResolvedValue("No cover available");
    const el = await mount();
    buttons(el)
      .find((b) => b.label === "Assign")
      .click();
    await flush();
    expect(assignCover).toHaveBeenCalledWith({
      sessionId: "a0X1",
      coverUserId: "005B",
      note: null
    });
    buttons(el)
      .find((b) => b.label === "Cancel")
      .click();
    await flush();
    await flush();
    expect(cancelForAbsence).toHaveBeenCalledWith({
      sessionId: "a0X1",
      reason: "No cover available"
    });
    buttons(el)
      .find((b) => b.label === "Withdraw")
      .click();
    await flush();
    expect(withdrawAbsence).toHaveBeenCalledWith({ absenceId: "a0S1" });
  });

  it("shows an all-clear state and opens the absence dialog", async () => {
    getDesk.mockResolvedValue({ ...DESK, absences: [], uncovered: [] });
    AbsenceModal.open.mockResolvedValue(null);
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain(
      "Every upcoming session has a teacher."
    );
    buttons(el)
      .find((b) => b.label === "Report absence")
      .click();
    await flush();
    expect(AbsenceModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ canArrange: true, teachers: DESK.teachers })
    );
  });

  it("is read-only for teachers", async () => {
    getDesk.mockResolvedValue({
      ...DESK,
      canArrange: false,
      currentUserId: "005Z"
    });
    const el = await mount();
    expect(buttons(el).find((b) => b.label === "Assign")).toBeUndefined();
    expect(buttons(el).find((b) => b.label === "Withdraw")).toBeUndefined();
  });
});
