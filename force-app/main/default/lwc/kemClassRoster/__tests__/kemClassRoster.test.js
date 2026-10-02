import { createElement } from "lwc";
import KemClassRoster from "c/kemClassRoster";
import getRoster from "@salesforce/apex/EnrolmentController.getRoster";

jest.mock(
  "@salesforce/apex/EnrolmentController.getRoster",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.withdraw",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.decideDiscount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.searchLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.getEnrollableClasses",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.previewEnrolment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.enrol",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const ROSTER = {
  canApproveDiscounts: true,
  seatsTaken: 2,
  offering: {
    Id: "0kF000000000001",
    Name: "Maths Sat AM",
    LearningCourse: { Name: "Mathematics" },
    Branch__r: { Name: "Bengaluru" },
    Delivery_Mode__c: "Classroom",
    Class_Status__c: "Open",
    EnrollmentCapacity: 3
  },
  rows: [
    {
      enrolmentId: "0kX000000000001",
      learnerName: "Ananya Sharma",
      status: "Enrolled",
      agreedTotal: 15281,
      discountCode: "SIBLING10",
      discountApproval: "Pending",
      billingStatus: "Not Invoiced"
    },
    {
      enrolmentId: "0kX000000000002",
      learnerName: "Arjun Sharma",
      status: "Enrolled",
      agreedTotal: 16331,
      discountApproval: "Not Required",
      billingStatus: "Invoiced"
    }
  ]
};

describe("c-kem-class-roster", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the seat meter and roster with discount actions", async () => {
    const element = createElement("c-kem-class-roster", { is: KemClassRoster });
    element.recordId = "0kF000000000001";
    document.body.appendChild(element);
    getRoster.emit(ROSTER);
    await Promise.resolve();
    expect(element.shadowRoot.querySelector(".meter-big").textContent).toBe(
      "2"
    );
    expect(element.shadowRoot.querySelector(".meter-caption").textContent).toBe(
      "1 seat left"
    );
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(2);
    const approveItems = [
      ...element.shadowRoot.querySelectorAll("lightning-menu-item")
    ].filter((i) => i.value === "approve");
    expect(approveItems).toHaveLength(1);
  });
});
