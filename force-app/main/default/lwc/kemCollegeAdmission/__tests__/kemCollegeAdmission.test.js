import { createElement } from "lwc";
import KemCollegeAdmission from "c/kemCollegeAdmission";
import getAdmission from "@salesforce/apex/CollegeAdmissionController.getAdmission";
import verifyDocument from "@salesforce/apex/CollegeAdmissionController.verifyDocument";
import admit from "@salesforce/apex/CollegeAdmissionController.admit";

jest.mock(
  "@salesforce/apex/CollegeAdmissionController.getAdmission",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.captureConsent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.verifyDocument",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.markDocumentsVerified",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.scheduleInterview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.recordOutcome",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.admit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.reject",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);

function admission(overrides = {}) {
  return {
    id: "0iT1",
    student: "Ravi Kumar",
    branch: "BE CSE",
    campus: "Yelahanka Campus",
    entryRoute: "Regular",
    stage: "Processing",
    eligibility: "Eligible",
    eligibilityNotes: "Meets the rule.",
    suggestions: [],
    consent: true,
    canDesk: true,
    canDean: false,
    items: [
      {
        id: "0dI1",
        name: "Aadhaar card",
        required: true,
        status: "New",
        sensitiveClass: "Identity"
      }
    ],
    ...overrides
  };
}

function mount() {
  const element = createElement("c-kem-college-admission", {
    is: KemCollegeAdmission
  });
  element.recordId = "0iT1";
  document.body.appendChild(element);
  return element;
}

describe("c-kem-college-admission", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("verifies an identity document with only the last four digits", async () => {
    getAdmission.mockResolvedValue(admission());
    verifyDocument.mockResolvedValue(admission());
    const element = mount();
    await flush();
    const last4 = element.shadowRoot.querySelector(
      'lightning-input[data-id="0dI1"]'
    );
    last4.value = "4321";
    byProp(element.shadowRoot, "lightning-button", "label", "Verify").click();
    await flush();
    expect(verifyDocument).toHaveBeenCalledWith({
      applicationId: "0iT1",
      itemId: "0dI1",
      last4: "4321"
    });
    expect(
      byProp(element.shadowRoot, "lightning-button", "label", "Admit")
    ).toBeUndefined();
  });

  it("shows suggestions when the student is not eligible", async () => {
    getAdmission.mockResolvedValue(
      admission({
        eligibility: "Not Eligible",
        eligibilityNotes: "This branch needs 90.00%; the student has 86.00%.",
        suggestions: ["BE Civil Engineering (needs 60%)"]
      })
    );
    const element = mount();
    await flush();
    expect(
      element.shadowRoot.querySelector(".suggestions").textContent
    ).toContain("BE Civil Engineering");
  });

  it("lets the Dean admit after a passed interview", async () => {
    getAdmission.mockResolvedValue(
      admission({ stage: "Ready For Decision", outcome: "Pass", canDean: true })
    );
    admit.mockResolvedValue(
      admission({
        stage: "Fee Pending",
        canDean: true,
        programmeEnrolmentId: "a0P1",
        enrolmentStatus: "Provisional"
      })
    );
    const element = mount();
    await flush();
    byProp(element.shadowRoot, "lightning-button", "label", "Admit").click();
    await flush();
    expect(admit).toHaveBeenCalledWith({ applicationId: "0iT1" });
    expect(element.shadowRoot.querySelector(".enrolled").textContent).toContain(
      "Provisional"
    );
  });

  it("stays empty for learning-centre applications", async () => {
    getAdmission.mockResolvedValue(null);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector("header")).toBeNull();
  });
});
