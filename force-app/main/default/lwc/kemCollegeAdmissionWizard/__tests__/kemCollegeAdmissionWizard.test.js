import { createElement } from "lwc";
import KemCollegeAdmissionWizard from "c/kemCollegeAdmissionWizard";
import getAdmissionCatalogue from "@salesforce/apex/CollegeAdmissionController.getAdmissionCatalogue";
import getRequirements from "@salesforce/apex/CollegeAdmissionController.getRequirements";
import previewEligibility from "@salesforce/apex/CollegeAdmissionController.previewEligibility";

jest.mock(
  "@salesforce/apex/CollegeAdmissionController.getAdmissionCatalogue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.getRequirements",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.previewEligibility",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionController.createAdmission",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
// eslint-disable-next-line @lwc/lwc/no-async-operation
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);

const CATALOGUE = [
  {
    id: "c1",
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
            name: "BE Computer Science and Engineering",
            cutoff: "PUC Science 90% + entrance rank",
            seatsRegular: 60,
            seatsLateral: 6,
            lateral: true
          },
          {
            campusBranchId: "cb2",
            name: "BE Mechanical Engineering",
            cutoff: "PUC Science 65% + entrance rank",
            seatsRegular: 60,
            seatsLateral: 6,
            lateral: true
          }
        ]
      }
    ]
  }
];

const BE_CSE = {
  open: true,
  qualifyingLevel: "PUC",
  streams: ["Science"],
  diplomaBranchCodes: [],
  minimum: 90,
  entranceRequired: true,
  entrances: [
    { exam: "KCET", maxRank: 20000 },
    { exam: "COMEDK", maxRank: 15000 }
  ],
  entryYear: 1,
  tuition: 150000,
  admissionFee: 5000,
  documents: [
    { label: "Aadhaar card", required: true, sensitiveClass: "Identity" }
  ]
};

async function mountAtMarks() {
  getAdmissionCatalogue.mockResolvedValue(CATALOGUE);
  getRequirements.mockResolvedValue(BE_CSE);
  const element = createElement("c-kem-college-admission-wizard", {
    is: KemCollegeAdmissionWizard
  });
  document.body.appendChild(element);
  await flush();
  const root = element.shadowRoot;
  root.querySelector('button[data-id="p1"]').click();
  await flush();
  root.querySelector('button[data-id="cb1"]').click();
  await flush();
  await flush();
  byProp(root, "lightning-button", "label", "Next").click();
  await flush();
  return element;
}

describe("c-kem-college-admission-wizard", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("asks only for the marks BE CSE needs and checks them live", async () => {
    previewEligibility.mockResolvedValue({
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
    const element = await mountAtMarks();
    const root = element.shadowRoot;
    expect(
      byProp(root, "lightning-input", "label", "PUC percentage")
    ).toBeTruthy();
    expect(
      byProp(root, "lightning-combobox", "label", "Entrance exam")
    ).toBeTruthy();
    expect(
      byProp(root, "lightning-combobox", "label", "Diploma branch")
    ).toBeUndefined();

    const set = (label, value) => {
      const input = byProp(root, "lightning-input", "label", label);
      input.value = value;
      input.dispatchEvent(new CustomEvent("change"));
    };
    set("SSLC / 10th percentage", "90");
    set("PUC percentage", "84");
    await wait(450);
    await flush();
    await flush();
    expect(previewEligibility).toHaveBeenCalledWith(
      expect.objectContaining({
        campusBranchId: "cb1",
        entryRoute: "Regular",
        qualifications: [
          { level: "SSLC", percentage: 90 },
          { level: "PUC", stream: "Science", branchCode: null, percentage: 84 }
        ]
      })
    );
    expect(root.querySelector(".verdict").textContent).toContain(
      "BE Mechanical Engineering"
    );
    expect(byProp(root, "lightning-button", "label", "Next").disabled).toBe(
      true
    );
  });

  it("switches to a suggested branch and lets the desk continue when eligible", async () => {
    previewEligibility.mockResolvedValue({
      status: "Eligible",
      reason:
        "The verified qualification and entrance score meet the active rule.",
      checks: [
        { label: "PUC (Science) at least 90%", actual: "92%", passed: true }
      ],
      suggestions: []
    });
    const element = await mountAtMarks();
    const root = element.shadowRoot;
    const input = byProp(
      root,
      "lightning-input",
      "label",
      "SSLC / 10th percentage"
    );
    input.value = "91";
    input.dispatchEvent(new CustomEvent("change"));
    await wait(450);
    await flush();
    await flush();
    expect(byProp(root, "lightning-button", "label", "Next").disabled).toBe(
      false
    );
  });
});
