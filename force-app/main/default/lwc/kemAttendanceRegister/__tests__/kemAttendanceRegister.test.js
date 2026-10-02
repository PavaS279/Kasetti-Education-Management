import { createElement } from "lwc";
import KemAttendanceRegister from "c/kemAttendanceRegister";
import getRegister from "@salesforce/apex/AttendanceController.getRegister";
import saveRegister from "@salesforce/apex/AttendanceController.saveRegister";

jest.mock(
  "@salesforce/apex/AttendanceController.getRegister",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AttendanceController.saveRegister",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const REGISTER = {
  canMark: true,
  alreadyMarked: false,
  session: {
    Id: "a0S000000000001",
    Start__c: "2026-10-03T03:30:00.000Z",
    Status__c: "Scheduled",
    Course_Offering__r: { Name: "Maths Sat AM" }
  },
  rows: [
    {
      learnerContactId: "003000000000001",
      enrolmentId: "0kX000000000001",
      learnerName: "Ananya Sharma",
      attendanceRate: 100,
      belowThreshold: false
    },
    {
      learnerContactId: "003000000000002",
      enrolmentId: "0kX000000000002",
      learnerName: "Arjun Sharma",
      attendanceRate: 50,
      belowThreshold: true
    }
  ]
};

describe("c-kem-attendance-register", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("marks learners and saves the register", async () => {
    getRegister.mockResolvedValue(JSON.parse(JSON.stringify(REGISTER)));
    saveRegister.mockResolvedValue(undefined);
    const element = createElement("c-kem-attendance-register", {
      is: KemAttendanceRegister
    });
    element.recordId = "a0S000000000001";
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelectorAll("li.row")).toHaveLength(2);
    expect(
      element.shadowRoot.querySelector(".kem-badge_danger").textContent
    ).toBe("50% attendance");

    const allPresent = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Mark all present");
    allPresent.click();
    await flush();
    const late = element.shadowRoot.querySelector(
      'button[data-id="003000000000002"][data-value="Late"]'
    );
    late.click();
    await flush();
    expect(late.getAttribute("aria-pressed")).toBe("true");
    const values = [
      ...element.shadowRoot.querySelectorAll(".counter-value")
    ].map((n) => n.textContent);
    expect(values).toEqual(["1", "1", "0", "0", "0"]);

    const save = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Save register");
    save.click();
    await flush();
    expect(saveRegister).toHaveBeenCalledWith(
      expect.objectContaining({
        sessionId: "a0S000000000001",
        teacherAttendance: "Present",
        rows: [
          expect.objectContaining({ status: "Present" }),
          expect.objectContaining({ status: "Late" })
        ]
      })
    );
  });
});
