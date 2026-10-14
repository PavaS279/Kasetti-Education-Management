import { createElement } from "lwc";
import KemCollegeDues from "c/kemCollegeDues";
import getDues from "@salesforce/apex/CollegeAdmissionsController.getDues";

jest.mock(
  "@salesforce/apex/CollegeAdmissionsController.getDues",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function mount() {
  const element = createElement("c-kem-college-dues", { is: KemCollegeDues });
  document.body.appendChild(element);
  return element;
}

describe("c-kem-college-dues", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows totals and one row per campus branch and year", async () => {
    const row = {
      key: "k",
      campus: "Yelahanka Campus",
      programme: "BE",
      branch: "CSE",
      academicYear: "2026-27",
      billed: 300000,
      paid: 150000,
      due: 150000,
      awaitingClearance: 50000,
      expiringSoon: 1,
      feeHolds: 0
    };
    getDues.mockResolvedValue({ rows: [row], total: row });
    const element = mount();
    await flush();
    const table = element.shadowRoot.querySelector("lightning-datatable");
    expect(table.data).toHaveLength(1);
    expect(element.shadowRoot.querySelector(".totals").textContent).toContain(
      "Expiring soon 1"
    );
  });

  it("renders nothing when there are no college invoices", async () => {
    getDues.mockResolvedValue({ rows: [], total: {} });
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector("section")).toBeNull();
  });

  it("shows the error message when loading fails", async () => {
    getDues.mockRejectedValue({ body: { message: "No access" } });
    const element = mount();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("No access");
  });
});
