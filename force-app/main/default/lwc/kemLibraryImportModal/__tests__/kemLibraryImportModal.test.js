import { createElement } from "lwc";
import KemLibraryImportModal from "c/kemLibraryImportModal";
import previewImport from "@salesforce/apex/LibrarySetupController.previewImport";
import importItems from "@salesforce/apex/LibrarySetupController.importItems";

jest.mock(
  "@salesforce/apex/LibrarySetupController.previewImport",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibrarySetupController.importItems",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const CSV = "Title,Code,Copies\nWings of Fire,KT-BK-101,3\n";

describe("c-kem-library-import-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("previews pasted lines and imports them", async () => {
    previewImport.mockResolvedValue({
      newItems: 1,
      addCopies: 1,
      errors: 1,
      copies: 5,
      rows: [
        {
          line: 2,
          title: "Wings of Fire",
          code: "KT-BK-101",
          itemType: "Book",
          copies: 3,
          action: "New"
        },
        {
          line: 3,
          title: "Abacus Workbook",
          code: "KT-BK-OLD",
          itemType: "Book",
          copies: 2,
          action: "Add copies",
          message: "Abacus Workbook: 5 → 7 copies"
        },
        {
          line: 4,
          title: "",
          code: "X",
          itemType: "Book",
          copies: 1,
          action: "Error",
          message: "No title"
        }
      ]
    });
    importItems.mockResolvedValue({
      created: 1,
      updated: 1,
      copies: 5,
      skipped: 1
    });
    const element = createElement("c-kem-library-import-modal", {
      is: KemLibraryImportModal
    });
    element.branchId = "a0M1";
    element.branchName = "KT Edutech Indiranagar";
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const button = (label) =>
      [...root.querySelectorAll("lightning-button")].find((b) =>
        (b.label || "").startsWith(label)
      );
    expect(root.querySelector("a[download]").getAttribute("href")).toContain(
      "data:text/csv"
    );
    expect(button("Preview").disabled).toBe(true);
    const paste = root.querySelector("lightning-textarea");
    paste.value = CSV;
    paste.dispatchEvent(new CustomEvent("change"));
    await settle();
    button("Preview").click();
    await settle();
    expect(previewImport).toHaveBeenCalledWith({ branchId: "a0M1", csv: CSV });
    expect(root.querySelectorAll("tbody tr")).toHaveLength(3);
    expect(root.textContent).toContain(
      "1 new · 1 with copies added · 5 copies in all · 1 skipped"
    );
    expect(root.textContent).toContain("5 → 7 copies");
    button("Import 2 lines").click();
    await settle();
    expect(importItems).toHaveBeenCalledWith({ branchId: "a0M1", csv: CSV });
    expect(closed.mock.calls[0][0].detail).toEqual({
      created: 1,
      updated: 1,
      copies: 5,
      skipped: 1
    });
  });

  it("explains a file it cannot read", async () => {
    previewImport.mockRejectedValue({
      body: { message: "The header row needs at least Title and Code columns." }
    });
    const element = createElement("c-kem-library-import-modal", {
      is: KemLibraryImportModal
    });
    element.branchId = "a0M1";
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const paste = root.querySelector("lightning-textarea");
    paste.value = "Name\nX";
    paste.dispatchEvent(new CustomEvent("change"));
    await settle();
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Preview")
      .click();
    await settle();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "Title and Code"
    );
    expect(
      [...root.querySelectorAll("lightning-button")].find((b) =>
        (b.label || "").startsWith("Import")
      ).disabled
    ).toBe(true);
  });
});
