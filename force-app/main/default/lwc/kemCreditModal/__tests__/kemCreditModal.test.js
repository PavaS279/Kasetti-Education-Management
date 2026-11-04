import { createElement } from "lwc";
import KemCreditModal from "c/kemCreditModal";
import issueCreditNote from "@salesforce/apex/CreditController.issueCreditNote";

jest.mock(
  "@salesforce/apex/CreditController.issueCreditNote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-credit-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("validates the amount against what was paid and issues the credit", async () => {
    issueCreditNote.mockResolvedValue("a0C000000000001");
    const element = createElement("c-kem-credit-modal", { is: KemCreditModal });
    element.invoiceId = "a0I000000000001";
    element.invoiceNumber = "BLR-000001";
    element.paid = 7080;
    document.body.appendChild(element);
    await flush();
    const issue = () =>
      [...element.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Issue credit note"
      );
    const amount = element.shadowRoot.querySelector("lightning-input");
    const reason = element.shadowRoot.querySelector("lightning-textarea");
    amount.value = "9000";
    amount.dispatchEvent(new CustomEvent("change"));
    reason.value = "Left after one month";
    reason.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(issue().disabled).toBe(true);
    amount.value = "3000";
    amount.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(issue().disabled).toBe(false);
    issue().click();
    await flush();
    expect(issueCreditNote).toHaveBeenCalledWith({
      request: {
        sourceInvoiceId: "a0I000000000001",
        amount: 3000,
        origin: "Withdrawal",
        reason: "Left after one month"
      }
    });
  });
});
