import { createElement } from "lwc";
import KemInsights from "c/kemInsights";
import getInsights from "@salesforce/apex/InsightsController.getInsights";

jest.mock(
  "@salesforce/apex/InsightsController.getInsights",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const now = new Date();
const DATA = {
  userFirstName: "Asha",
  showAdmissions: true,
  openEnquiries: 12,
  newEnquiriesThisWeek: 3,
  applicationsInReview: 4,
  readyForDecision: 2,
  offersAwaitingResponse: 1,
  showClasses: true,
  seatCapacity: 40,
  seatsTaken: 30,
  activeClasses: 3,
  showAttendance: true,
  attendanceRate30Days: 88.4,
  learnersBelowThreshold: 2,
  showFinance: true,
  outstanding: 12000,
  overdue: 4000,
  collectedThisMonth: 32801,
  reconciliationExceptions: 1,
  discountsAwaitingApproval: 0,
  dashboardId: "01Z000000000001",
  todaysSessions: [
    {
      id: "a0S1",
      className: "Maths Sat AM",
      startAt: now.toISOString(),
      endAt: new Date(now.getTime() + 3600000).toISOString(),
      room: "Room 1",
      teacher: "Meena",
      status: "Scheduled",
      attendanceMarked: false
    }
  ]
};

describe("c-kem-insights", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the sections the user can see", async () => {
    getInsights.mockResolvedValue(DATA);
    const element = createElement("c-kem-insights", { is: KemInsights });
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".kem-hero__title").textContent).toContain(
      "Asha"
    );
    expect(root.querySelector(".ring span").textContent).toBe("75%");
    expect(root.textContent).toContain("88%");
    expect(root.textContent).toContain("To mark");
    expect(root.querySelectorAll(".alert")).toHaveLength(2);
    expect(root.querySelectorAll(".tile")).toHaveLength(3);
    expect(root.querySelector(".money-value").value).toBe(12000);
  });

  it("hides finance and admissions for a teacher", async () => {
    getInsights.mockResolvedValue({
      ...DATA,
      showAdmissions: false,
      showFinance: false,
      learnersBelowThreshold: 0,
      reconciliationExceptions: 0,
      todaysSessions: []
    });
    const element = createElement("c-kem-insights", { is: KemInsights });
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".tiles")).toBeNull();
    expect(root.querySelector(".money")).toBeNull();
    expect(root.textContent).toContain("No classes today.");
  });
});
