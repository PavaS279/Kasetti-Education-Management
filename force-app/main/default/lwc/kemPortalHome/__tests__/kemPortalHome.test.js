import { createElement } from "lwc";
import KemPortalHome from "c/kemPortalHome";
import getHome from "@salesforce/apex/PortalController.getHome";
import getLearner from "@salesforce/apex/PortalController.getLearner";
import markMessageRead from "@salesforce/apex/PortalController.markMessageRead";
import downloadDocument from "@salesforce/apex/PortalController.downloadDocument";

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

jest.mock(
  "@salesforce/apex/PortalController.markMessageRead",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalController.downloadDocument",
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

  it("shows the inbox, grades, documents, plans, waitlist and credit", async () => {
    const home = {
      ...HOME,
      unreadMessages: 1,
      messages: [
        {
          id: "a0M1",
          subject: "Report card for Ananya",
          body: "Dear Rohit, the report card is ready.",
          sentOn: new Date().toISOString(),
          read: false
        }
      ]
    };
    const rich = {
      ...detail("003A", "Ananya Sharma"),
      creditBalance: 500,
      grades: [
        {
          enrolmentId: "0x61",
          className: "Maths Sat AM",
          score: 92.67,
          grade: "A+",
          status: "Final",
          reportCardVersionId: "068A"
        }
      ],
      documents: [
        {
          versionId: "068A",
          title: "Report Card Ananya",
          kind: "Report Card",
          createdDate: new Date().toISOString()
        },
        {
          versionId: "068B",
          title: "Invoice BLR-000005",
          kind: "Invoice",
          createdDate: new Date().toISOString()
        }
      ],
      waitlist: [
        { id: "a0W1", className: "Art Club", status: "Waiting", position: 2 }
      ],
      invoices: [
        {
          id: "a0I1",
          invoiceNumber: "BLR-000005",
          className: "Coding Club",
          billingPeriod: "Sep 2026",
          dueDate: "2026-10-20",
          balance: 2130,
          status: "Partially Paid",
          instalments: [
            {
              sequence: 1,
              dueDate: "2026-10-20",
              amount: 1376.66,
              status: "Paid"
            },
            {
              sequence: 2,
              dueDate: "2026-11-20",
              amount: 1376.66,
              status: "Partially Paid",
              overdue: true
            }
          ]
        }
      ]
    };
    getHome.mockResolvedValue(home);
    getLearner.mockResolvedValue(rich);
    markMessageRead.mockResolvedValue(undefined);
    downloadDocument.mockResolvedValue({
      fileName: "report.pdf",
      base64: "JVBERi0="
    });
    const element = createElement("c-kem-portal-home", { is: KemPortalHome });
    document.body.appendChild(element);
    await flush();
    await flush();
    const root = element.shadowRoot;

    expect(root.querySelector(".inbox-button").textContent).toContain("1 new");
    root.querySelector(".inbox-button").click();
    await flush();
    root.querySelector(".message-head").click();
    await flush();
    expect(markMessageRead).toHaveBeenCalledWith({ messageId: "a0M1" });
    expect(root.querySelector(".message-body").textContent).toContain(
      "report card is ready"
    );
    expect(root.querySelector(".inbox-button").textContent).not.toContain(
      "new"
    );

    expect(root.textContent).toContain("Number 2 on the waiting list.");

    root.querySelector('button[data-value="results"]').click();
    await flush();
    expect(root.textContent).toContain("92.7%");
    expect(root.textContent).toContain("Final");

    root.querySelector('button[data-value="fees"]').click();
    await flush();
    expect(root.querySelectorAll(".step")).toHaveLength(2);
    expect(root.querySelector(".step_overdue")).toBeTruthy();
    expect(root.querySelector(".credit")).toBeTruthy();
    expect(root.textContent).toContain("Sep 2026");

    root.querySelector('button[data-value="documents"]').click();
    await flush();
    expect(root.querySelectorAll(".doc")).toHaveLength(2);
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Download")
      .click();
    await flush();
    expect(downloadDocument).toHaveBeenCalledWith({ versionId: "068A" });
  });
});
