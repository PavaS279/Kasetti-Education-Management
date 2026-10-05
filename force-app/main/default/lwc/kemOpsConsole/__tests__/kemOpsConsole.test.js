import { createElement } from "lwc";
import KemOpsConsole from "c/kemOpsConsole";
import getConsole from "@salesforce/apex/OpsController.getConsole";
import ensureSchedules from "@salesforce/apex/OpsController.ensureSchedules";
import runNow from "@salesforce/apex/OpsController.runNow";

jest.mock(
  "@salesforce/apex/OpsController.getConsole",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OpsController.ensureSchedules",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OpsController.runNow",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function consoleData(overrides = {}) {
  return {
    health: "failing",
    issues: [
      "KEM Recurring Billing is not scheduled.",
      "1 sessions needing cover."
    ],
    generatedAt: "2026-10-05T10:00:00.000Z",
    schedules: [
      {
        name: "KEM Message Dispatch",
        state: "WAITING",
        nextRun: "2026-10-05T11:20:00.000Z",
        missing: false
      },
      { name: "KEM Recurring Billing", state: "NOT SCHEDULED", missing: true }
    ],
    runs: [
      {
        id: "707A",
        job: "RecurringBillingJob",
        jobType: "BatchApex",
        status: "Completed",
        itemsProcessed: 1,
        totalItems: 1,
        errors: 0,
        createdDate: "2026-10-05T09:00:00.000Z",
        problem: false
      },
      {
        id: "707B",
        job: "DocumentService",
        jobType: "Queueable",
        status: "Failed",
        detail: "Callout failed",
        createdDate: "2026-10-05T09:30:00.000Z",
        problem: true
      }
    ],
    queues: [
      {
        key: "cover",
        label: "Sessions needing cover",
        count: 1,
        severity: "error",
        guidance: "Cover Desk"
      },
      {
        key: "refunds",
        label: "Refunds awaiting approval",
        count: 0,
        severity: "warning"
      }
    ],
    errorSources: [{ source: "DocumentService.Job", count: 1 }],
    recentErrors: [
      {
        Id: "a0E1",
        Name: "LOG-000001",
        Source__c: "DocumentService.Job",
        Message__c: "Boom",
        CreatedDate: "2026-10-05T09:31:00.000Z"
      }
    ],
    errorsLast24h: 1,
    ...overrides
  };
}

async function mount() {
  const el = createElement("c-kem-ops-console", { is: KemOpsConsole });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-kem-ops-console", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows health, queues, schedules, runs and errors", async () => {
    getConsole.mockResolvedValue(consoleData());
    const el = await mount();
    const root = el.shadowRoot;
    expect(root.querySelector(".health_bad").textContent).toContain(
      "Action required"
    );
    expect(root.querySelectorAll(".issues li")).toHaveLength(2);
    expect(root.querySelector(".tile_error").textContent).toContain(
      "Sessions needing cover"
    );
    expect(root.querySelectorAll(".job")).toHaveLength(2);
    expect(root.querySelector(".run_bad").textContent).toContain(
      "Callout failed"
    );
    const toggle = [...root.querySelectorAll("lightning-button")].find((b) =>
      b.label.startsWith("Show errors")
    );
    toggle.click();
    await flush();
    expect(root.querySelectorAll(".error")).toHaveLength(1);
  });

  it("schedules missing jobs and runs a job now", async () => {
    getConsole.mockResolvedValue(consoleData());
    ensureSchedules.mockResolvedValue(1);
    runNow.mockResolvedValue("707C");
    const el = await mount();
    [...el.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Schedule missing jobs")
      .click();
    await flush();
    expect(ensureSchedules).toHaveBeenCalled();
    el.shadowRoot
      .querySelector('lightning-button-icon[data-name="KEM Message Dispatch"]')
      .click();
    await flush();
    expect(runNow).toHaveBeenCalledWith({ jobName: "KEM Message Dispatch" });
  });

  it("is healthy when nothing needs attention", async () => {
    getConsole.mockResolvedValue(
      consoleData({ health: "healthy", issues: [], runs: [], recentErrors: [] })
    );
    const el = await mount();
    expect(el.shadowRoot.querySelector(".health_ok").textContent).toContain(
      "All systems normal"
    );
    expect(el.shadowRoot.textContent).toContain("No background runs");
  });

  it("stays hidden for users who are not administrators", async () => {
    getConsole.mockRejectedValue({
      body: { message: "The operations console is for administrators." }
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });
});
