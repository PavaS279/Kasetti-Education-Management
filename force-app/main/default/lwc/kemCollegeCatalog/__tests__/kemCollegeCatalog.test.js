import { createElement } from "lwc";
import KemCollegeCatalog from "c/kemCollegeCatalog";
import getDashboard from "@salesforce/apex/CollegeCatalogController.getDashboard";

jest.mock(
  "@salesforce/apex/CollegeCatalogController.getDashboard",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const row = (id, name, overrides = {}) => ({
  id,
  name,
  detail: "2026-27",
  status: "Active",
  metric: null,
  ...overrides
});

function data() {
  return {
    campuses: [row("a01", "Yelahanka Campus")],
    programmes: [row("a02", "Bachelor of Engineering")],
    branches: [row("a03", "Computer Science")],
    campusBranches: [row("a04", "Computer Science", { metric: 132 })],
    sections: [row("a05", "Section A", { metric: 60 })],
    subjects: [row("a06", "21MAT11 · Engineering Mathematics I")],
    sectionSubjects: 1
  };
}

describe("c-kem-college-catalog", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("uses college wording and shows all catalogue groups", async () => {
    getDashboard.mockResolvedValue(data());
    const element = createElement("c-kem-college-catalog", {
      is: KemCollegeCatalog
    });
    document.body.appendChild(element);
    await flush();

    expect(element.shadowRoot.querySelector("h1").textContent).toBe(
      "College overview"
    );
    expect(element.shadowRoot.querySelectorAll(".card")).toHaveLength(6);
    expect(element.shadowRoot.textContent).toContain("Yelahanka Campus");
    expect(element.shadowRoot.textContent).toContain("132 seats");
    expect(element.shadowRoot.textContent).toContain("1 section subjects");
  });

  it("shows an actionable access error", async () => {
    getDashboard.mockRejectedValue({
      body: { message: "You do not have access to the college catalogue." }
    });
    const element = createElement("c-kem-college-catalog", {
      is: KemCollegeCatalog
    });
    document.body.appendChild(element);
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("do not have access");
  });
});
