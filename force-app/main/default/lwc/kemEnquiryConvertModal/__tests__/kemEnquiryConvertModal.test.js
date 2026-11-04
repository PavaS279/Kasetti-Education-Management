import { createElement } from "lwc";
import KemEnquiryConvertModal from "c/kemEnquiryConvertModal";
import getConversionPreview from "@salesforce/apex/EnquiryController.getConversionPreview";
import convertEnquiry from "@salesforce/apex/EnquiryController.convertEnquiry";

jest.mock(
  "@salesforce/apex/EnquiryController.getConversionPreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnquiryController.convertEnquiry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);

function preview(college) {
  return {
    enquiry: {
      FirstName: "Ravi",
      LastName: "Kumar",
      Email: "ravi@example.com",
      Branch__r: { Name: "Yelahanka Campus" }
    },
    hasGuardianDetails: false,
    college
  };
}

function mount() {
  const element = createElement("c-kem-enquiry-convert-modal", {
    is: KemEnquiryConvertModal
  });
  element.recordId = "00Q1";
  element.label = "Convert enquiry";
  document.body.appendChild(element);
  return element;
}

describe("c-kem-enquiry-convert-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("converts a college enquiry only after the desk confirms the marks", async () => {
    getConversionPreview.mockResolvedValue(
      preview({
        campusBranchName: "YLK BE CSE 2026-27",
        entryRoute: "Regular",
        canConvert: true,
        qualifications: [{ level: "PUC", stream: "Science", percentage: 92 }],
        entrances: [{ exam: "KCET", rank: 12400 }]
      })
    );
    convertEnquiry.mockResolvedValue({ learnerId: "001L1" });
    const element = mount();
    await settle();

    const convert = byProp(
      element.shadowRoot,
      "lightning-button",
      "label",
      "Convert"
    );
    expect(convert.disabled).toBe(true);
    expect(
      byProp(
        element.shadowRoot,
        "lightning-input",
        "label",
        "Create admissions application"
      )
    ).toBeUndefined();

    const puc = byProp(
      element.shadowRoot,
      "lightning-input",
      "label",
      "PUC Science"
    );
    puc.value = "93";
    puc.dispatchEvent(new CustomEvent("change"));
    const confirm = byProp(
      element.shadowRoot,
      "lightning-input",
      "label",
      "I have checked these marks against the marks card"
    );
    confirm.checked = true;
    confirm.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(convert.disabled).toBe(false);

    convert.click();
    await settle();
    const request = convertEnquiry.mock.calls[0][0].request;
    expect(request.marksConfirmed).toBe(true);
    expect(request.qualifications).toEqual([
      { level: "PUC", stream: "Science", percentage: 93 }
    ]);
    expect(request.entrances).toEqual([{ exam: "KCET", rank: 12400 }]);
  });

  it("tells a school counsellor that only the college desk can convert", async () => {
    getConversionPreview.mockResolvedValue(
      preview({
        campusBranchName: "YLK BE CSE 2026-27",
        entryRoute: "Regular",
        canConvert: false,
        qualifications: [],
        entrances: []
      })
    );
    const element = mount();
    await settle();
    expect(element.shadowRoot.textContent).toContain(
      "Only the college admission desk can convert"
    );
    expect(
      byProp(element.shadowRoot, "lightning-button", "label", "Convert")
        .disabled
    ).toBe(true);
  });

  it("keeps the school conversion unchanged", async () => {
    getConversionPreview.mockResolvedValue(preview(undefined));
    convertEnquiry.mockResolvedValue({ learnerId: "001L1" });
    const element = mount();
    await settle();
    byProp(element.shadowRoot, "lightning-button", "label", "Convert").click();
    await settle();
    const request = convertEnquiry.mock.calls[0][0].request;
    expect(request.createApplication).toBe(true);
    expect(request.marksConfirmed).toBeUndefined();
  });
});
