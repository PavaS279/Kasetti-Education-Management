import { createElement } from "lwc";
import KemCollegeRecordHeader from "c/kemCollegeRecordHeader";
import getRecordHeader from "@salesforce/apex/CollegeCatalogController.getRecordHeader";

jest.mock(
  "@salesforce/apex/CollegeCatalogController.getRecordHeader",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-college-record-header", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows app-specific college wording", async () => {
    getRecordHeader.mockResolvedValue({
      label: "Branch",
      name: "Computer Science",
      detail: "BE · CS"
    });
    const element = createElement("c-kem-college-record-header", {
      is: KemCollegeRecordHeader
    });
    element.recordId = "0vY000000000001";
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelector(".label").textContent).toBe(
      "Branch"
    );
    expect(element.shadowRoot.querySelector("h1").textContent).toBe(
      "Computer Science"
    );
    expect(element.shadowRoot.textContent).toContain("BE · CS");
  });
});
