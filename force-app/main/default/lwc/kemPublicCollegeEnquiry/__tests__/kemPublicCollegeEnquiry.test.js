import { createElement } from "lwc";
import KemPublicCollegeEnquiry from "c/kemPublicCollegeEnquiry";
import getCatalogue from "@salesforce/apex/CollegePublicController.getCatalogue";
import getRequirements from "@salesforce/apex/CollegePublicController.getRequirements";
import checkEligibility from "@salesforce/apex/CollegePublicController.checkEligibility";
import submit from "@salesforce/apex/PublicEnquiryController.submit";

jest.mock(
  "@salesforce/apex/CollegePublicController.getCatalogue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegePublicController.getRequirements",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegePublicController.checkEligibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PublicEnquiryController.submit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
// eslint-disable-next-line @lwc/lwc/no-async-operation
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const byLabel = (root, selector, label) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el.label === label);

const CATALOGUE = [
  {
    id: "c1",
    code: "KTC-YLK",
    name: "Yelahanka Campus",
    academicYear: "2026-27",
    programmes: [
      {
        id: "p1",
        name: "Bachelor of Engineering (BE)",
        years: 4,
        branches: [
          {
            campusBranchId: "cb1",
            externalId: "KTC-BR-BCS",
            name: "BE Computer Science and Engineering",
            cutoff: "PUC Science 90% + entrance rank",
            lateral: true
          },
          {
            campusBranchId: "cb2",
            externalId: "KTC-BR-BME",
            name: "BE Mechanical Engineering",
            cutoff: "PUC Science 65% + entrance rank",
            lateral: true
          }
        ]
      }
    ]
  }
];

const REQUIREMENTS = {
  open: true,
  qualifyingLevel: "PUC",
  streams: ["Science"],
  diplomaBranchCodes: [],
  entranceRequired: true,
  entrances: [{ exam: "KCET", maxRank: 20000 }],
  tuition: 150000,
  admissionFee: 5000,
  documents: [
    { label: "Aadhaar card", required: true },
    { label: "PAN card", required: false }
  ]
};

function set(root, label, value) {
  const input = byLabel(root, "lightning-input", label);
  if (input.type === "checkbox") {
    input.checked = value;
  } else {
    input.value = value;
  }
  input.dispatchEvent(new CustomEvent("change"));
}

function click(root, text) {
  Array.from(root.querySelectorAll("button"))
    .find((b) => b.textContent.trim() === text)
    .click();
}

describe("c-kem-public-college-enquiry", () => {
  beforeEach(() => {
    window.scrollTo = jest.fn();
  });
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("guides the visitor from branch to marks to a sent enquiry", async () => {
    getCatalogue.mockResolvedValue(CATALOGUE);
    getRequirements.mockResolvedValue(REQUIREMENTS);
    checkEligibility.mockResolvedValue({
      status: "Not Eligible",
      reason: "This branch needs 90%; the student has 84%.",
      checks: [
        { label: "PUC (Science) at least 90%", actual: "84%", passed: false }
      ],
      suggestions: [
        {
          campusBranchId: "cb2",
          branch: "BE Mechanical Engineering",
          minimum: 65
        }
      ]
    });
    submit.mockResolvedValue({ accepted: true, reference: "ABC123" });
    const element = createElement("c-kem-public-college-enquiry", {
      is: KemPublicCollegeEnquiry
    });
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;

    root.querySelector('button[data-id="p1"]').click();
    await flush();
    root.querySelector('button[data-id="cb1"]').click();
    await flush();
    await flush();
    click(root, "Continue");
    await flush();

    // Only the fields BE needs.
    expect(byLabel(root, "lightning-input", "PUC percentage")).toBeTruthy();
    expect(
      byLabel(root, "lightning-combobox", "Diploma branch")
    ).toBeUndefined();
    set(root, "SSLC / 10th percentage", "90");
    set(root, "PUC percentage", "84");
    await wait(500);
    await flush();
    expect(checkEligibility).toHaveBeenCalledWith(
      expect.objectContaining({ campusBranchId: "cb1", entryRoute: "Regular" })
    );
    expect(root.querySelector(".verdict").textContent).toContain(
      "BE Mechanical Engineering"
    );
    click(root, "Continue");
    await flush();

    set(root, "Student last name", "Nayak");
    set(root, "Student mobile", "9845000000");
    await flush();
    click(root, "Continue");
    await flush();
    expect(root.querySelector(".review").textContent).toContain("₹1,55,000");

    set(
      root,
      "I consent to KT College using these details to respond to this admission enquiry.",
      true
    );
    await flush();
    click(root, "Send enquiry");
    await flush();
    const request = submit.mock.calls[0][0].request;
    expect(request.branchCode).toBe("KTC-YLK");
    expect(request.courseExternalId).toBe("KTC-BR-BCS");
    expect(request.message).toContain("PUC Science: 84%");
    expect(request.message).toContain("Self-check: Not Eligible");
    expect(request.submissionId).toMatch(/^portal-/);
    await flush();
    expect(root.querySelector(".success").textContent).toContain("ABC123");
  });

  it("shows a message when admissions are closed", async () => {
    getCatalogue.mockResolvedValue([]);
    const element = createElement("c-kem-public-college-enquiry", {
      is: KemPublicCollegeEnquiry
    });
    document.body.appendChild(element);
    await flush();
    expect(
      element.shadowRoot.querySelector(".error-panel").textContent
    ).toContain("not open");
  });
});
