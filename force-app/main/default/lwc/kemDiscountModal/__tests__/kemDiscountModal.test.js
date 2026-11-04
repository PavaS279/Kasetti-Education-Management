import { createElement } from "lwc";
import KemDiscountModal from "c/kemDiscountModal";
import getOverview from "@salesforce/apex/DiscountSetupController.getOverview";
import saveDiscount from "@salesforce/apex/DiscountSetupController.saveDiscount";

jest.mock(
  "@salesforce/apex/DiscountSetupController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DiscountSetupController.saveDiscount",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);

describe("c-kem-discount-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("creates a code, tidying it and showing an example", async () => {
    getOverview.mockResolvedValue({
      branches: [{ label: "Indiranagar", value: "a0M1" }],
      courses: [],
      discounts: []
    });
    saveDiscount
      .mockRejectedValueOnce({
        body: { message: "The code DIWALI15 is already used." }
      })
      .mockResolvedValueOnce("a0DNEW");
    const element = createElement("c-kem-discount-modal", {
      is: KemDiscountModal
    });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const form = element.shadowRoot.querySelector(
      "c-kem-discount-form"
    ).shadowRoot;
    const set = async (field, value) => {
      const el = form.querySelector(`[data-field="${field}"]`);
      el.value = value;
      el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
      await settle();
    };
    const save = () =>
      [...form.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Create discount"
      );
    expect(save().disabled).toBe(true);
    await set("code", "diwali 15");
    expect(form.querySelector('[data-field="code"]').value).toBe("DIWALI15");
    await set("value", "15");
    expect(form.textContent).toContain("₹375 off");
    await set("branchId", "a0M1");
    form
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((i) => {
        i.reportValidity = () => true;
      });
    save().click();
    await settle();
    expect(form.querySelector('[role="alert"]').textContent).toContain(
      "already used"
    );
    save().click();
    await settle();
    expect(saveDiscount.mock.calls[1][0].request).toMatchObject({
      id: null,
      code: "DIWALI15",
      discountType: "Percentage",
      value: 15,
      feeType: "Tuition",
      branchId: "a0M1",
      courseId: null,
      maxUses: null,
      active: true
    });
    expect(closed.mock.calls[0][0].detail).toBe("a0DNEW");
  });
});
