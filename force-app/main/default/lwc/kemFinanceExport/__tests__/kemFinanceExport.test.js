import { createElement } from "lwc";
import KemFinanceExport from "c/kemFinanceExport";
import getBranches from "@salesforce/apex/FinanceExportController.getBranches";
import getRecent from "@salesforce/apex/FinanceExportController.getRecent";
import preview from "@salesforce/apex/FinanceExportController.preview";
import runExport from "@salesforce/apex/FinanceExportController.runExport";

jest.mock(
  "@salesforce/apex/FinanceExportController.getBranches",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FinanceExportController.getRecent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FinanceExportController.preview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FinanceExportController.runExport",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const EXPORT = {
  exportId: "a0X000000000001",
  exportNumber: "EXP-000001",
  fromDate: "2026-10-01",
  toDate: "2026-10-05",
  runType: "Manual",
  lines: 12,
  documents: 4,
  fileId: "069000000000001"
};

async function mount() {
  const el = createElement("c-kem-finance-export", { is: KemFinanceExport });
  document.body.appendChild(el);
  await flush();
  return el;
}

const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-finance-export", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("previews account totals and exports the CSV", async () => {
    getBranches.mockResolvedValue([
      { label: "Bengaluru (BLR-01)", value: "a0M000000000001" }
    ]);
    getRecent.mockResolvedValueOnce([]).mockResolvedValueOnce([EXPORT]);
    preview.mockResolvedValue({
      documents: 4,
      balanced: true,
      totalDebit: 2760,
      totalCredit: 2760,
      accounts: [
        {
          account: "1100",
          accountName: "Accounts receivable",
          debit: 1180,
          credit: 1180
        },
        { account: "4000", accountName: "Revenue", debit: 0, credit: 1000 }
      ]
    });
    runExport.mockResolvedValue(EXPORT);
    const el = await mount();
    expect(
      el.shadowRoot.querySelector("lightning-combobox").options
    ).toHaveLength(2);
    expect(el.shadowRoot.textContent).toContain("No exports yet.");

    const combo = el.shadowRoot.querySelector("lightning-combobox");
    combo.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a0M000000000001" } })
    );
    const dates = el.shadowRoot.querySelectorAll("lightning-input");
    dates[0].value = "2026-10-01";
    dates[0].dispatchEvent(new CustomEvent("change"));
    dates[1].value = "2026-10-05";
    dates[1].dispatchEvent(new CustomEvent("change"));
    button(el, "Preview").click();
    await flush();
    expect(preview).toHaveBeenCalledWith({
      fromDate: "2026-10-01",
      toDate: "2026-10-05",
      branchId: "a0M000000000001"
    });
    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(2);
    expect(el.shadowRoot.querySelector(".kem-badge_success").textContent).toBe(
      "Balanced"
    );

    button(el, "Export CSV").click();
    await flush();
    await flush();
    expect(runExport).toHaveBeenCalled();
    const link = el.shadowRoot.querySelector("a.download");
    expect(link.href).toContain(
      "/sfc/servlet.shepherd/document/download/069000000000001"
    );
    expect(el.shadowRoot.querySelector(".export").textContent).toContain(
      "2026-10-01 – 2026-10-05"
    );
  });

  it("shows an empty period, server errors and stays hidden without access", async () => {
    getBranches.mockResolvedValue([]);
    getRecent.mockResolvedValue([]);
    preview.mockResolvedValue({ documents: 0, balanced: true, accounts: [] });
    runExport.mockRejectedValue({
      body: { message: "Export at most 92 days at a time." }
    });
    const el = await mount();
    button(el, "Preview").click();
    await flush();
    expect(el.shadowRoot.textContent).toContain("No finance documents");
    button(el, "Export CSV").click();
    await flush();
    expect(
      el.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("92 days");

    getBranches.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'FinanceExportController'."
      }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("section")).toBeNull();
  });
});
