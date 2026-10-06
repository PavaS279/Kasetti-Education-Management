import { createElement } from "lwc";
import KemAnalytics from "c/kemAnalytics";
import getDashboard from "@salesforce/apex/AnalyticsController.getDashboard";
import getBranches from "@salesforce/apex/AnalyticsController.getBranches";

jest.mock(
  "@salesforce/apex/AnalyticsController.getDashboard",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AnalyticsController.getBranches",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function month(key, label, overrides = {}) {
  return {
    key,
    label,
    invoiced: 0,
    collected: 0,
    newEnrolments: 0,
    withdrawals: 0,
    attendanceRate: null,
    attendanceMarks: 0,
    ...overrides
  };
}

function dashboard(overrides = {}) {
  return {
    months: [
      month("2026-08", "Aug 26", {
        invoiced: 10000,
        collected: 8000,
        newEnrolments: 4,
        attendanceRate: 92.5,
        attendanceMarks: 40
      }),
      month("2026-09", "Sep 26", {
        invoiced: 12000,
        collected: 6000,
        newEnrolments: 2,
        withdrawals: 1
      }),
      month("2026-10", "Oct 26", {
        invoiced: 5000,
        collected: 7000,
        attendanceRate: 75,
        attendanceMarks: 20
      })
    ],
    cohorts: [
      {
        key: "2026-09",
        label: "Sep 2026",
        enrolled: 4,
        active: 3,
        withdrawn: 1,
        retention: 75
      },
      {
        key: "2026-10",
        label: "Oct 2026",
        enrolled: 0,
        active: 0,
        withdrawn: 0,
        retention: null
      }
    ],
    ageing: [
      { key: "current", label: "Not yet due", amount: 3000, invoices: 2 },
      { key: "1-30", label: "1–30 days", amount: 1500, invoices: 1 },
      { key: "90+", label: "Over 90 days", amount: 0, invoices: 0 }
    ],
    courses: [
      {
        course: "Maths",
        classes: 2,
        capacity: 20,
        seatsTaken: 15,
        fillRate: 75,
        averageScore: 81.5
      }
    ],
    showFinance: true,
    showEnrolments: true,
    showAttendance: true,
    invoicedTotal: 27000,
    collectedTotal: 21000,
    collectionRate: 77.8,
    retentionRate: 75,
    newEnrolmentsTotal: 6,
    withdrawalsTotal: 1,
    ...overrides
  };
}

async function mount(props = {}) {
  const el = createElement("c-kem-analytics", { is: KemAnalytics });
  Object.assign(el, props);
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-kem-analytics", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders tiles, charts, cohorts, ageing and courses", async () => {
    getBranches.mockResolvedValue([{ label: "Bengaluru", value: "a0M1" }]);
    getDashboard.mockResolvedValue(dashboard());
    const el = await mount();
    const root = el.shadowRoot;
    expect(root.querySelectorAll(".tile")).toHaveLength(6);
    expect(root.querySelector(".tile").textContent).toContain("Invoiced");
    expect(root.querySelectorAll("figure")).toHaveLength(6);
    expect(root.querySelectorAll("path.s1-fill").length).toBeGreaterThan(0);
    expect(root.querySelectorAll("circle.dot")).toHaveLength(2);
    expect(root.querySelector("path.line").getAttribute("d")).toMatch(/^M/);
    expect(root.querySelector(".seq-3").textContent).toBe("75%");
    expect(root.querySelectorAll(".ageing-row")).toHaveLength(3);
    expect(root.querySelector(".data-table td").textContent).toBe("Maths");
    expect(getDashboard).toHaveBeenCalledWith({ branchId: null, months: 12 });
  });

  it("shows a tooltip on hover and hides it on leave", async () => {
    getBranches.mockResolvedValue([]);
    getDashboard.mockResolvedValue(dashboard());
    const el = await mount();
    const hit = el.shadowRoot.querySelector('rect.hit[data-chart="revenue"]');
    hit.dispatchEvent(new CustomEvent("mouseenter"));
    await flush();
    const tip = el.shadowRoot.querySelector(".tooltip");
    expect(tip.textContent).toContain("Aug 26");
    expect(tip.textContent).toContain("Invoiced");
    el.shadowRoot
      .querySelector("figure")
      .dispatchEvent(new CustomEvent("mouseleave"));
    await flush();
    expect(el.shadowRoot.querySelector(".tooltip")).toBeNull();

    el.shadowRoot
      .querySelector('rect.hit[data-chart="enrolments"]')
      .dispatchEvent(new CustomEvent("mouseenter"));
    await flush();
    expect(el.shadowRoot.querySelector(".tooltip").textContent).toContain(
      "New 4"
    );
    el.shadowRoot
      .querySelector('rect.hit[data-chart="attendance"]')
      .dispatchEvent(new CustomEvent("mouseenter"));
    await flush();
    expect(el.shadowRoot.querySelector(".tooltip").textContent).toContain(
      "92.5%"
    );
  });

  it("switches to the table view and reloads on filter changes", async () => {
    getBranches.mockResolvedValue([]);
    getDashboard.mockResolvedValue(dashboard());
    const el = await mount({ recordId: "a0M1" });
    expect(getDashboard).toHaveBeenCalledWith({ branchId: "a0M1", months: 12 });
    const button = el.shadowRoot.querySelector("lightning-button");
    button.click();
    await flush();
    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(3);
    expect(el.shadowRoot.querySelector("svg")).toBeNull();
    const [, period] = el.shadowRoot.querySelectorAll("lightning-combobox");
    period.dispatchEvent(new CustomEvent("change", { detail: { value: "6" } }));
    await flush();
    expect(getDashboard).toHaveBeenLastCalledWith({
      branchId: "a0M1",
      months: 6
    });
    const [branch] = el.shadowRoot.querySelectorAll("lightning-combobox");
    branch.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    await flush();
    expect(getDashboard).toHaveBeenLastCalledWith({
      branchId: null,
      months: 6
    });
  });

  it("omits finance for users without it and hides without access", async () => {
    getBranches.mockRejectedValue(new Error("x"));
    getDashboard.mockResolvedValue(
      dashboard({ showFinance: false, courses: [] })
    );
    const el = await mount();
    expect(el.shadowRoot.querySelectorAll(".tile")).toHaveLength(3);
    expect(el.shadowRoot.textContent).toContain("No running classes.");

    getDashboard.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'AnalyticsController'."
      }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
