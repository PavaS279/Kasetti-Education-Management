import { createElement } from "lwc";
import KemBranches from "c/kemBranches";
import getOverview from "@salesforce/apex/BranchController.getOverview";
import BranchCloneModal from "c/kemBranchCloneModal";

jest.mock(
  "@salesforce/apex/BranchController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemBranchCloneModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function kpi(overrides) {
  return {
    branchId: "a00000000000001",
    name: "Indiranagar",
    code: "BLR-01",
    city: "Bengaluru",
    active: true,
    rooms: 3,
    activeClasses: 4,
    plannedClasses: 0,
    capacity: 60,
    seatsTaken: 45,
    fillRate: 75,
    learners: 40,
    waiting: 2,
    attendanceRate: 91.5,
    openEnquiries: 6,
    outstanding: 12000,
    overdue: 0,
    collectedThisMonth: 50000,
    ...overrides
  };
}

function overview(overrides = {}) {
  return {
    branches: [
      kpi({}),
      kpi({
        branchId: "a00000000000002",
        name: "Whitefield",
        code: "WFD-01",
        activeClasses: 0,
        plannedClasses: 3,
        capacity: 0,
        seatsTaken: 0,
        fillRate: null,
        learners: 0,
        attendanceRate: 62,
        overdue: 500
      })
    ],
    totals: kpi({ name: "All branches", fillRate: 75 }),
    showFinance: true,
    canCreateBranch: true,
    ...overrides
  };
}

function render(props = {}) {
  const element = createElement("c-kem-branches", { is: KemBranches });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const buttons = (element) => [
  ...element.shadowRoot.querySelectorAll("lightning-button")
];

describe("c-kem-branches", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows totals and a card per branch with warnings", async () => {
    getOverview.mockResolvedValue(overview());
    const element = render();
    await flush();
    const totals = element.shadowRoot.querySelectorAll(".total");
    expect(totals.length).toBe(6);
    expect(totals[0].textContent).toContain("2");
    const cards = element.shadowRoot.querySelectorAll(".branch");
    expect(cards.length).toBe(2);
    expect(cards[0].textContent).toContain("Indiranagar");
    expect(cards[0].textContent).toContain("75%");
    expect(cards[0].textContent).toContain("BLR-01 · Bengaluru");
    expect(cards[1].textContent).toContain("0 + 3 planned");
    expect(cards[1].textContent).toContain("—");
    expect(cards[1].querySelectorAll(".metric-value_warn").length).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll("lightning-formatted-number").length
    ).toBe(6);
    expect(
      buttons(element).filter((b) => b.label === "Use as template").length
    ).toBe(2);
  });

  it("sorts branches", async () => {
    getOverview.mockResolvedValue(overview());
    const element = render();
    await flush();
    const sort = element.shadowRoot.querySelector("lightning-combobox");
    sort.dispatchEvent(
      new CustomEvent("change", { detail: { value: "attendanceRate" } })
    );
    await flush();
    const cards = element.shadowRoot.querySelectorAll(".branch");
    expect(cards[0].textContent).toContain("Indiranagar");
    sort.dispatchEvent(
      new CustomEvent("change", { detail: { value: "fillRate" } })
    );
    await flush();
    expect(
      element.shadowRoot.querySelectorAll(".branch")[1].textContent
    ).toContain("Whitefield");
  });

  it("highlights the current branch and clones it", async () => {
    getOverview.mockResolvedValue(overview());
    BranchCloneModal.open.mockResolvedValue("a00000000000003");
    const element = render({ recordId: "a00000000000001" });
    await flush();
    expect(
      element.shadowRoot.querySelector(".branch_current").textContent
    ).toContain("This branch");
    const cloneThis = buttons(element).find(
      (b) => b.label === "New branch from this one"
    );
    cloneThis.click();
    await flush();
    await flush();
    expect(BranchCloneModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ branchId: "a00000000000001" })
    );
    expect(getOverview).toHaveBeenCalledTimes(2);
  });

  it("does not reload when cloning is cancelled", async () => {
    getOverview.mockResolvedValue(overview());
    BranchCloneModal.open.mockResolvedValue(null);
    const element = render();
    await flush();
    buttons(element)
      .find((b) => b.label === "Use as template")
      .click();
    await flush();
    expect(BranchCloneModal.open).toHaveBeenCalled();
    expect(getOverview).toHaveBeenCalledTimes(1);
  });

  it("hides cloning and finance when not allowed", async () => {
    getOverview.mockResolvedValue(
      overview({ canCreateBranch: false, showFinance: false })
    );
    const element = render({ recordId: "a00000000000001" });
    await flush();
    expect(buttons(element).length).toBe(0);
    expect(
      element.shadowRoot.querySelectorAll("lightning-formatted-number").length
    ).toBe(0);
  });

  it("shows an empty state and errors", async () => {
    getOverview.mockResolvedValue(overview({ branches: [] }));
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();

    getOverview.mockRejectedValue({ body: { message: "No access" } });
    element.shadowRoot.querySelector("lightning-button-icon").click();
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("No access");
  });
});
