import { createElement } from "lwc";
import KemDiscountManagerModal from "c/kemDiscountManagerModal";
import getOverview from "@salesforce/apex/DiscountSetupController.getOverview";
import setActive from "@salesforce/apex/DiscountSetupController.setActive";
import saveDiscount from "@salesforce/apex/DiscountSetupController.saveDiscount";

jest.mock(
  "@salesforce/apex/DiscountSetupController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DiscountSetupController.setActive",
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

const OVERVIEW = {
  canEdit: true,
  branches: [{ label: "Indiranagar", value: "a0M1" }],
  courses: [{ label: "Python for Kids", value: "0ZV1" }],
  discounts: [
    {
      id: "a0D1",
      code: "SIBLING10",
      description: "Sibling discount 10%",
      discountType: "Percentage",
      value: 10,
      feeType: "Tuition",
      timesUsed: 12,
      maxUses: null,
      active: true,
      status: "Active",
      enrolments: 12,
      amountGiven: 18450,
      pendingApprovals: 0,
      requiresApproval: false
    },
    {
      id: "a0D2",
      code: "ADMWAIVE",
      discountType: "Fixed Amount",
      value: 1000,
      feeType: "Admission",
      timesUsed: 2,
      maxUses: 20,
      active: true,
      status: "Active",
      enrolments: 2,
      amountGiven: 2000,
      pendingApprovals: 1,
      requiresApproval: true,
      validTo: "2026-12-31"
    },
    {
      id: "a0D3",
      code: "OLD",
      discountType: "Percentage",
      value: 5,
      timesUsed: 0,
      active: false,
      status: "Inactive",
      enrolments: 0,
      amountGiven: 0,
      pendingApprovals: 0
    }
  ]
};

describe("c-kem-discount-manager-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists codes with their use, edits one and switches one off", async () => {
    getOverview.mockResolvedValue(OVERVIEW);
    saveDiscount.mockResolvedValue("a0D2");
    setActive.mockResolvedValue();
    const element = createElement("c-kem-discount-manager-modal", {
      is: KemDiscountManagerModal
    });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    expect(root.querySelectorAll("li.code")).toHaveLength(2);
    const text = root.textContent;
    expect(text).toContain("SIBLING10");
    expect(text).toContain("10% off");
    expect(text).toContain("₹1,000 off");
    expect(text).toContain("2 of 20 used");
    expect(text).toContain("1 waiting for approval");
    expect(text).toContain("Needs approval");

    const toggle = root.querySelector("lightning-input");
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent("change"));
    await settle();
    expect(root.querySelectorAll("li.code")).toHaveLength(3);

    const edit = [...root.querySelectorAll("lightning-button")].filter(
      (b) => b.label === "Edit"
    )[1];
    edit.click();
    await settle();
    const form = root.querySelector("c-kem-discount-form");
    expect(form.discount.code).toBe("ADMWAIVE");
    const value = form.shadowRoot.querySelector('[data-field="value"]');
    value.value = "1500";
    value.dispatchEvent(
      new CustomEvent("change", { detail: { value: "1500" } })
    );
    await settle();
    form.shadowRoot
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((i) => {
        i.reportValidity = () => true;
      });
    [...form.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Save changes")
      .click();
    await settle();
    expect(saveDiscount.mock.calls[0][0].request).toMatchObject({
      id: "a0D2",
      code: "ADMWAIVE",
      discountType: "Fixed Amount",
      value: 1500,
      feeType: "Admission",
      requiresApproval: true,
      validTo: "2026-12-31"
    });
    expect(root.querySelector("c-kem-discount-form")).toBeNull();

    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Switch off")
      .click();
    await settle();
    expect(setActive).toHaveBeenCalledWith({
      discountId: "a0D1",
      active: false
    });
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Done")
      .click();
    expect(closed.mock.calls[0][0].detail).toBe(true);
  });
});
