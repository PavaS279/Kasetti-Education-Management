import { createElement } from "lwc";
import KemEnquiryModal from "c/kemEnquiryModal";

describe("c-kem-enquiry-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function mount() {
    const element = createElement("c-kem-enquiry-modal", {
      is: KemEnquiryModal
    });
    element.branchId = "a0M000000000001";
    document.body.appendChild(element);
    return element;
  }

  it("shows the education fields and no Company field", () => {
    const element = mount();
    const fields = [
      ...element.shadowRoot.querySelectorAll("lightning-input-field")
    ].map((f) => f.fieldName);
    expect(fields).toEqual(
      expect.arrayContaining([
        "LastName",
        "Learner_Birthdate__c",
        "Guardian_First_Name__c",
        "Branch__c",
        "Interested_Course__c",
        "Enquiry_Channel__c"
      ])
    );
    expect(fields).not.toContain("Company");
  });

  it("requires a way to contact the family", async () => {
    const element = mount();
    const form = element.shadowRoot.querySelector("lightning-record-edit-form");
    form.submit = jest.fn();
    form.dispatchEvent(
      new CustomEvent("submit", {
        detail: { fields: { LastName: "Rao", Branch__c: "a0M000000000001" } }
      })
    );
    await Promise.resolve();
    expect(form.submit).not.toHaveBeenCalled();
    expect(element.shadowRoot.textContent).toContain(
      "at least one email address or phone number"
    );

    form.dispatchEvent(
      new CustomEvent("submit", {
        detail: {
          fields: { LastName: "Rao", Guardian_Phone__c: "+919800000000" }
        }
      })
    );
    await Promise.resolve();
    expect(form.submit).toHaveBeenCalledWith(
      expect.objectContaining({ Enquiry_Channel__c: "Walk-in" })
    );
  });
});
