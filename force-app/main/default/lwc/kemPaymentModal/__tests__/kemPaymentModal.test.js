import { createElement } from "lwc";
import KemPaymentModal from "c/kemPaymentModal";
import recordPayment from "@salesforce/apex/BillingController.recordPayment";

jest.mock(
  "@salesforce/apex/BillingController.recordPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const byProp = (root, selector, prop, value) =>
  Array.from(root.querySelectorAll(selector)).find((el) => el[prop] === value);

describe("c-kem-payment-modal", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("records a demand draft with its instrument details as pending", async () => {
    recordPayment.mockResolvedValue({ status: "Pending" });
    const element = createElement("c-kem-payment-modal", {
      is: KemPaymentModal
    });
    element.invoiceId = "a0I1";
    element.invoiceNumber = "YLK-000001";
    element.balance = 155000;
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    byProp(root, "lightning-combobox", "label", "Method").dispatchEvent(
      new CustomEvent("change", { detail: { value: "Demand Draft" } })
    );
    await flush();
    const set = (label, value) => {
      const input = byProp(root, "lightning-input", "label", label);
      input.value = value;
      input.dispatchEvent(new CustomEvent("change"));
    };
    set("Reference", "DD-1");
    set("DD / cheque number", "004512");
    set("Drawn on bank", "Canara Bank");
    set("DD / cheque date", "2026-10-14");
    root
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((input) => {
        input.reportValidity = () => true;
      });
    byProp(root, "lightning-button", "label", "Record payment").click();
    await flush();
    expect(recordPayment).toHaveBeenCalledWith({
      request: expect.objectContaining({
        method: "Demand Draft",
        confirmed: false,
        instrumentNumber: "004512",
        instrumentBank: "Canara Bank",
        instrumentDate: "2026-10-14"
      })
    });
  });
});
