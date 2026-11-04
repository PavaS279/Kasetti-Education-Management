import { createElement } from "lwc";
import KemRetentionDesk from "c/kemRetentionDesk";
import getDesk from "@salesforce/apex/RetentionController.getDesk";
import recordFollowUp from "@salesforce/apex/RetentionController.recordFollowUp";
import invite from "@salesforce/apex/RetentionController.invite";
import recalculate from "@salesforce/apex/RetentionController.recalculate";

jest.mock(
  "@salesforce/apex/RetentionController.getDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RetentionController.recordFollowUp",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RetentionController.invite",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RetentionController.recalculate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function desk(overrides = {}) {
  return {
    high: 1,
    medium: 1,
    followUpNeeded: 1,
    retained: 3,
    lastAssessed: "2026-10-06T04:05:00.000Z",
    canRecalculate: true,
    atRisk: [
      {
        enrolmentId: "0Pq1",
        learnerAccountId: "001A",
        learner: "Asha",
        className: "Maths A",
        branch: "Bengaluru",
        score: 65,
        level: "High",
        reasons: "Attendance 45%; Fees overdue 40 days",
        status: "Follow-up Needed"
      },
      {
        enrolmentId: "0Pq2",
        learnerAccountId: "001B",
        learner: "Ravi",
        className: "Maths A",
        branch: "Bengaluru",
        score: 30,
        level: "Medium",
        reasons: "Attendance 70%",
        note: "Called — Anil"
      }
    ],
    candidates: [
      {
        enrolmentId: "0Pq3",
        learner: "Kiran",
        className: "Robotics",
        endDate: "2026-10-30"
      },
      {
        enrolmentId: "0Pq4",
        learner: "Meera",
        className: "Robotics",
        endDate: "2026-10-30",
        invitedOn: "2026-10-01T10:00:00.000Z"
      }
    ],
    ...overrides
  };
}

async function mount(props = {}) {
  const el = createElement("c-kem-retention-desk", { is: KemRetentionDesk });
  Object.assign(el, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-retention-desk", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists at-risk learners and records a follow-up", async () => {
    getDesk.mockResolvedValue(desk());
    recordFollowUp.mockResolvedValue();
    const el = await mount({ recordId: "a0M1" });
    expect(getDesk).toHaveBeenCalledWith({ branchId: "a0M1", level: "All" });
    expect(el.shadowRoot.querySelectorAll(".count")).toHaveLength(4);
    const rows = el.shadowRoot.querySelectorAll(".row");
    expect(rows).toHaveLength(2);
    expect(rows[0].querySelector(".kem-badge_danger").textContent).toContain(
      "High · 65"
    );
    expect(rows[1].querySelector(".note").textContent).toContain("Called");

    rows[0].querySelector("lightning-button").click();
    await flush();
    expect(button(el, "Save follow-up").disabled).toBe(true);
    const note = el.shadowRoot.querySelector("lightning-textarea");
    note.value = "Spoke to the father";
    note.dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el, "Save follow-up").click();
    await flush();
    expect(recordFollowUp).toHaveBeenCalledWith({
      enrolmentId: "0Pq1",
      status: "Contacted",
      note: "Spoke to the father"
    });
    expect(getDesk).toHaveBeenCalledTimes(2);
  });

  it("filters by level, recalculates and handles a cancelled edit", async () => {
    getDesk.mockResolvedValue(desk());
    recalculate.mockResolvedValue("707X");
    const el = await mount();
    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "High" } }));
    await flush();
    expect(getDesk).toHaveBeenLastCalledWith({ branchId: null, level: "High" });
    button(el, "Recalculate").click();
    await flush();
    expect(recalculate).toHaveBeenCalled();
    el.shadowRoot.querySelector(".row lightning-button").click();
    await flush();
    const outcome = [
      ...el.shadowRoot.querySelectorAll("lightning-combobox")
    ][1];
    outcome.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Retained" } })
    );
    await flush();
    expect(button(el, "Save follow-up").disabled).toBe(false);
    button(el, "Cancel").click();
    await flush();
    expect(el.shadowRoot.querySelector(".editor")).toBeNull();
  });

  it("invites selected learners to re-enrol", async () => {
    getDesk.mockResolvedValue(desk());
    invite.mockResolvedValue(2);
    const el = await mount();
    el.shadowRoot.querySelectorAll(".tab")[1].click();
    await flush();
    const boxes = el.shadowRoot.querySelectorAll(".candidate lightning-input");
    expect(boxes).toHaveLength(2);
    expect(
      el.shadowRoot.querySelectorAll(".candidate")[1].textContent
    ).toContain("Invited");
    expect(button(el, "Send invitations (0)").disabled).toBe(true);
    boxes[0].checked = true;
    boxes[0].dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el, "Send invitations (1)").click();
    await flush();
    expect(invite).toHaveBeenCalledWith({ enrolmentIds: ["0Pq3"] });
  });

  it("shows empty states and stays hidden without access", async () => {
    getDesk.mockResolvedValue(
      desk({
        atRisk: [],
        candidates: [],
        lastAssessed: null,
        canRecalculate: false
      })
    );
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("No learners at risk.");
    expect(el.shadowRoot.textContent).toContain("Not scored yet");
    expect(button(el, "Recalculate")).toBeUndefined();
    el.shadowRoot.querySelectorAll(".tab")[1].click();
    await flush();
    expect(el.shadowRoot.textContent).toContain("No classes ending soon.");

    getDesk.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'RetentionController'."
      }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
