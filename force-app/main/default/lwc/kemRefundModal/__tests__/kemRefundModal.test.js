import { createElement } from "lwc";
import KemRefundModal from "c/kemRefundModal";
import requestRefund from "@salesforce/apex/CreditController.requestRefund";

jest.mock(
  "@salesforce/apex/CreditController.requestRefund",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

async function mount() {
  const element = createElement("c-kem-refund-modal", { is: KemRefundModal });
  element.creditNoteId = "a0C000000000001";
  element.creditNoteName = "CN-000001";
  element.payerName = "Rohit Sharma";
  element.available = 2500;
  element.autoApproveLimit = 1000;
  document.body.appendChild(element);
  await flush();
  return element;
}

const submit = (element) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === "Request refund"
  );

describe("c-kem-refund-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("defaults to the available amount and flags approval", async () => {
    const element = await mount();
    expect(element.shadowRoot.querySelector(".note_warn")).toBeTruthy();
    expect(submit(element).disabled).toBe(true);
    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "800";
    input.dispatchEvent(new CustomEvent("change"));
    const reason = element.shadowRoot.querySelector("lightning-textarea");
    reason.value = "Withdrawal";
    reason.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(element.shadowRoot.querySelector(".note_ok")).toBeTruthy();
    expect(submit(element).disabled).toBe(false);
  });

  it("submits the request and shows server errors", async () => {
    requestRefund.mockRejectedValue({
      body: { message: "Only 500.00 of this credit can be refunded" }
    });
    const element = await mount();
    const reason = element.shadowRoot.querySelector("lightning-textarea");
    reason.value = "Family moved";
    reason.dispatchEvent(new CustomEvent("change"));
    await flush();
    submit(element).click();
    await flush();
    expect(requestRefund).toHaveBeenCalledWith({
      request: {
        creditNoteId: "a0C000000000001",
        amount: 2500,
        method: "Bank Transfer",
        reason: "Family moved"
      }
    });
    expect(element.shadowRoot.textContent).toContain("Only 500.00");
  });
});
