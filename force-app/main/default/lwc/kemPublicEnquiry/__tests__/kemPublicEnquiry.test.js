import { createElement } from "lwc";
import KemPublicEnquiry from "c/kemPublicEnquiry";
import getFormData from "@salesforce/apex/PublicEnquiryController.getFormData";
import submit from "@salesforce/apex/PublicEnquiryController.submit";

jest.mock(
  "@salesforce/apex/PublicEnquiryController.getFormData",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PublicEnquiryController.submit",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

async function mount() {
  getFormData.mockResolvedValue({
    branches: [{ label: "Bengaluru Central", value: "BLR-01" }],
    courses: [{ label: "Robotics", value: "ROB-01" }],
    relationships: [{ label: "Father", value: "Father" }],
    deliveryModes: [{ label: "Classroom", value: "Classroom" }]
  });
  const element = createElement("c-kem-public-enquiry", {
    is: KemPublicEnquiry
  });
  document.body.appendChild(element);
  await flush();
  // The page first asks what the visitor is interested in.
  element.shadowRoot.querySelector('button[data-interest="courses"]').click();
  await flush();
  return element;
}

describe("c-kem-public-enquiry", () => {
  it("offers college admission or courses first", async () => {
    getFormData.mockResolvedValue({
      branches: [],
      courses: [],
      relationships: [],
      deliveryModes: []
    });
    const element = createElement("c-kem-public-enquiry", {
      is: KemPublicEnquiry
    });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelectorAll(".choice-card")).toHaveLength(2);
    element.shadowRoot.querySelector('button[data-interest="college"]').click();
    await flush();
    expect(
      element.shadowRoot.querySelector("c-kem-public-college-enquiry")
    ).not.toBeNull();
  });

  beforeEach(() => {
    window.scrollTo = jest.fn();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads public-safe branch and course choices", async () => {
    const element = await mount();
    expect(getFormData).toHaveBeenCalledTimes(1);
    const comboboxes =
      element.shadowRoot.querySelectorAll("lightning-combobox");
    expect(comboboxes[1].options).toEqual([
      { label: "Bengaluru Central", value: "BLR-01" }
    ]);
    expect(comboboxes[2].options).toContainEqual({
      label: "Robotics",
      value: "ROB-01"
    });
  });

  it("submits only after browser validation and shows the reference", async () => {
    submit.mockResolvedValue({ accepted: true, reference: "A1B2C3D4E5F6" });
    const element = await mount();
    const controls = element.shadowRoot.querySelectorAll(
      "lightning-input, lightning-combobox, lightning-textarea"
    );
    controls.forEach((control) => {
      control.checkValidity = jest.fn().mockReturnValue(true);
      control.reportValidity = jest.fn();
    });
    const values = {
      lastName: "Sharma",
      branchCode: "BLR-01",
      guardianEmail: "parent@example.com",
      privacyConsent: true
    };
    Object.entries(values).forEach(([field, value]) => {
      const control = element.shadowRoot.querySelector(
        `[data-field="${field}"]`
      );
      control.dispatchEvent(
        new CustomEvent("change", {
          detail: { value },
          bubbles: true,
          composed: true
        })
      );
    });
    await flush();
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(
        new CustomEvent("submit", { bubbles: true, composed: true })
      );
    await flush();
    expect(submit).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.textContent).toContain("A1B2C3D4E5F6");
  });
});
