import { createElement } from "lwc";
import KemPortalHome from "c/kemPortalHome";
import getHome from "@salesforce/apex/PortalController.getHome";
import getLearner from "@salesforce/apex/PortalController.getLearner";

jest.mock(
  "@salesforce/apex/PortalController.getHome",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalController.getLearner",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const tomorrow = new Date(Date.now() + 86400000);
const HOME = {
  viewerName: "Rohit",
  isGuardian: true,
  totalDue: 4080,
  learners: [
    { learnerContactId: "003A", name: "Ananya Sharma", activeClasses: 1 },
    { learnerContactId: "003B", name: "Arjun Sharma", activeClasses: 1 }
  ]
};

function detail(id, name) {
  return {
    learner: {
      learnerContactId: id,
      name,
      activeClasses: 1,
      attendanceRate: 92,
      balanceDue: 4080,
      overdueInvoices: 1,
      nextSessionStart: tomorrow.toISOString(),
      nextSessionClass: "Maths Sat AM"
    },
    classes: [],
    upcoming: [
      {
        id: "a0S1",
        className: "Maths Sat AM",
        startAt: tomorrow.toISOString(),
        endAt: new Date(tomorrow.getTime() + 3600000).toISOString(),
        room: "Room 1",
        status: "Scheduled",
        meetingUrl: "https://meet.example.com/x"
      }
    ],
    attendance: [
      {
        id: "a0T1",
        className: "Maths Sat AM",
        sessionStart: new Date().toISOString(),
        status: "Late",
        minutesLate: 12
      }
    ],
    results: [
      {
        id: "a0R1",
        assessment: "Unit Test 1",
        className: "Maths Sat AM",
        score: 47,
        maxScore: 50,
        percentage: 94,
        grade: "A+",
        absent: false
      }
    ],
    invoices: [
      {
        id: "a0I1",
        invoiceNumber: "BLR-000001",
        className: "Maths Sat AM",
        balance: 4080,
        status: "Partially Paid",
        overdue: true
      }
    ]
  };
}

describe("c-kem-portal-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("greets the guardian, switches learners and views", async () => {
    getHome.mockResolvedValue(HOME);
    getLearner.mockImplementation(({ learnerContactId }) =>
      Promise.resolve(
        detail(
          learnerContactId,
          learnerContactId === "003A" ? "Ananya Sharma" : "Arjun Sharma"
        )
      )
    );
    const element = createElement("c-kem-portal-home", { is: KemPortalHome });
    document.body.appendChild(element);
    await flush();
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".kem-hero__title").textContent).toContain(
      "Rohit"
    );
    expect(root.querySelector(".learner-name").textContent).toBe(
      "Ananya Sharma"
    );
    expect(root.textContent).toContain("Tomorrow");
    expect(root.querySelector("a.join").href).toContain("meet.example.com");

    root.querySelectorAll("button.chip")[1].click();
    await flush();
    expect(getLearner).toHaveBeenLastCalledWith({ learnerContactId: "003B" });
    expect(root.querySelector(".learner-name").textContent).toBe(
      "Arjun Sharma"
    );

    root.querySelector('button[data-value="results"]').click();
    await flush();
    expect(root.querySelector(".grade").textContent).toBe("A+");
    expect(root.textContent).toContain("47 / 50 · 94%");

    root.querySelector('button[data-value="attendance"]').click();
    await flush();
    expect(root.textContent).toContain("Late (12 min)");

    root.querySelector('button[data-value="fees"]').click();
    await flush();
    expect(root.querySelector(".invoice_overdue")).not.toBeNull();
  });

  it("explains when the user is not a portal user", async () => {
    getHome.mockRejectedValue({
      body: {
        message:
          "This page is for learners and guardians signed in to the portal."
      }
    });
    const element = createElement("c-kem-portal-home", { is: KemPortalHome });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("signed in to the portal");
  });
});
