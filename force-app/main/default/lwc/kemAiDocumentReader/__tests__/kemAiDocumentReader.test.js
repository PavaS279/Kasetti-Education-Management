import { createElement } from "lwc";
import KemAiDocumentReader from "c/kemAiDocumentReader";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import applicationDocuments from "@salesforce/apex/AiController.applicationDocuments";
import documentContent from "@salesforce/apex/AiController.documentContent";
import extractDocument from "@salesforce/apex/AiController.extractDocument";
import applyExtraction from "@salesforce/apex/AiController.applyExtraction";
import review from "@salesforce/apex/AiController.review";
import { readPdfText } from "c/kemPdfText";

jest.mock(
  "@salesforce/apex/AiController.isAvailable",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.applicationDocuments",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.documentContent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.extractDocument",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.applyExtraction",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/kemPdfText", () => ({ readPdfText: jest.fn() }), {
  virtual: true
});
jest.mock(
  "lightning/uiRecordApi",
  () => ({ notifyRecordUpdateAvailable: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const DOCS = [
  {
    contentVersionId: "068A",
    title: "Birth certificate",
    fileType: "PDF",
    sizeKb: 120,
    attachedTo: "Birth Certificate",
    readable: true
  },
  {
    contentVersionId: "068B",
    title: "Photo",
    fileType: "JPG",
    sizeKb: 800,
    attachedTo: "Application",
    readable: false,
    reason: "Only PDF and text files can be read (scanned images need OCR)."
  }
];

const EXTRACTION = {
  interactionId: "a0Z1",
  documentType: "Birth Certificate",
  found: 3,
  truncated: false,
  hasGuardian: false,
  proposals: [
    {
      key: "dateOfBirth",
      label: "Date of birth",
      section: "Learner",
      current: null,
      proposed: "2014-03-15",
      differs: true,
      selectable: true,
      selected: true
    },
    {
      key: "learnerLastName",
      label: "Last name",
      section: "Learner",
      current: "Rao",
      proposed: "Rao",
      differs: false,
      selectable: true,
      selected: false
    },
    {
      key: "guardianLastName",
      label: "Guardian last name",
      section: "Guardian",
      current: null,
      proposed: "Rao",
      differs: true,
      selectable: true,
      selected: true
    }
  ]
};

async function mount() {
  const el = createElement("c-kem-ai-document-reader", {
    is: KemAiDocumentReader
  });
  el.recordId = "0iT1";
  document.body.appendChild(el);
  isAvailable.emit(true);
  await flush();
  await flush();
  return el;
}

function button(el, label) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label || (b.label || "").startsWith(label)
  );
}

describe("c-kem-ai-document-reader", () => {
  beforeEach(() => {
    applicationDocuments.mockResolvedValue(DOCS);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists attached documents and blocks unreadable ones", async () => {
    const el = await mount();
    const docs = el.shadowRoot.querySelectorAll(".doc");
    expect(docs).toHaveLength(2);
    const buttons = el.shadowRoot.querySelectorAll(".doc lightning-button");
    expect(buttons[0].disabled).toBe(false);
    expect(buttons[1].disabled).toBe(true);
    expect(el.shadowRoot.textContent).toContain("scanned images need OCR");
  });

  it("reads a PDF, proposes details and applies the selected ones", async () => {
    documentContent.mockResolvedValue({ kind: "pdf", base64: "JVBERi0=" });
    readPdfText.mockResolvedValue({
      text: "Name of child: Ananya Rao. Date of birth 15/03/2014.",
      pages: 1
    });
    extractDocument.mockResolvedValue(EXTRACTION);
    applyExtraction.mockResolvedValue({
      learnerFields: 1,
      guardianAdded: true,
      guardianFields: 0,
      detailsNoted: false,
      outcome: "Accepted"
    });
    const el = await mount();
    el.shadowRoot.querySelector(".doc lightning-button").click();
    await flush();
    await flush();
    await flush();
    expect(readPdfText).toHaveBeenCalled();
    expect(extractDocument).toHaveBeenCalledWith({
      applicationId: "0iT1",
      documentName: "Birth certificate",
      text: "Name of child: Ananya Rao. Date of birth 15/03/2014."
    });
    expect(el.shadowRoot.textContent).toContain("3 details found");
    expect(el.shadowRoot.textContent).toContain("No guardian is linked yet");
    expect(button(el, "Apply").label).toBe("Apply 2 selected");

    // Correct a value, untick the guardian, then apply.
    const value = el.shadowRoot.querySelector(
      'lightning-input.value[data-key="dateOfBirth"]'
    );
    value.value = "2014-03-16";
    value.dispatchEvent(new CustomEvent("change"));
    const pick = el.shadowRoot.querySelector(
      'lightning-input.pick[data-key="guardianLastName"]'
    );
    pick.checked = false;
    pick.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(button(el, "Apply").label).toBe("Apply 1 selected");
    button(el, "Apply").click();
    await flush();
    await flush();
    expect(applyExtraction).toHaveBeenCalledWith({
      applicationId: "0iT1",
      interactionId: "a0Z1",
      documentName: "Birth certificate",
      changes: [{ key: "dateOfBirth", value: "2014-03-16" }]
    });
    expect(el.shadowRoot.textContent).toContain(
      "1 learner details updated, guardian added"
    );
  });

  it("reads pasted text and records a discard as rejected", async () => {
    extractDocument.mockResolvedValue(EXTRACTION);
    review.mockResolvedValue();
    const el = await mount();
    const group = el.shadowRoot.querySelector("lightning-radio-group");
    group.dispatchEvent(
      new CustomEvent("change", { detail: { value: "paste" } })
    );
    await flush();
    const area = el.shadowRoot.querySelector("lightning-textarea");
    area.value = "Application form. Learner name: Riya Shah. Born 02/07/2015.";
    area.dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el, "Read text").click();
    await flush();
    await flush();
    expect(extractDocument.mock.calls[0][0].documentName).toBe("Pasted text");
    button(el, "Discard").click();
    await flush();
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({ interactionId: "a0Z1", outcome: "Rejected" })
    );
    expect(el.shadowRoot.querySelector("lightning-radio-group")).not.toBeNull();
  });

  it("explains when a PDF has no text layer", async () => {
    documentContent.mockResolvedValue({ kind: "pdf", base64: "JVBERi0=" });
    readPdfText.mockResolvedValue({ text: "", pages: 1 });
    const el = await mount();
    el.shadowRoot.querySelector(".doc lightning-button").click();
    await flush();
    await flush();
    expect(extractDocument).not.toHaveBeenCalled();
    expect(el.shadowRoot.textContent).toContain("no readable text");
  });

  it("stays hidden without access", async () => {
    const el = createElement("c-kem-ai-document-reader", {
      is: KemAiDocumentReader
    });
    document.body.appendChild(el);
    isAvailable.emit(false);
    await flush();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
    expect(applicationDocuments).not.toHaveBeenCalled();
  });
});
