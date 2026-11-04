import { createElement } from "lwc";
import KemDocuments from "c/kemDocuments";
import getDocuments from "@salesforce/apex/DocumentController.getDocuments";
import generateDocument from "@salesforce/apex/DocumentController.generateDocument";

jest.mock(
  "@salesforce/apex/DocumentController.getDocuments",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DocumentController.generateDocument",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-documents", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("creates the PDF when none exists and lists it", async () => {
    getDocuments.mockResolvedValueOnce([]).mockResolvedValueOnce([
      {
        contentDocumentId: "069000000000001",
        title: "Invoice BLR-000001",
        kind: "Invoice",
        createdDate: new Date().toISOString(),
        createdBy: "Finance User"
      }
    ]);
    generateDocument.mockResolvedValue("069000000000001");
    const element = createElement("c-kem-documents", { is: KemDocuments });
    element.recordId = "a0I000000000001";
    element.objectApiName = "Student_Invoice__c";
    document.body.appendChild(element);
    await flush();
    const button = element.shadowRoot.querySelector("lightning-button");
    expect(button.label).toBe("Create invoice pdf");
    button.click();
    await flush();
    await flush();
    expect(generateDocument).toHaveBeenCalledWith({
      recordId: "a0I000000000001"
    });
    expect(element.shadowRoot.textContent).toContain("Invoice BLR-000001");
    expect(button.label).toBe("Open invoice pdf");
  });
});
