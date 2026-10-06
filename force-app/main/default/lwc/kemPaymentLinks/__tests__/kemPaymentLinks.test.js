import { createElement } from "lwc";
import KemPaymentLinks from "c/kemPaymentLinks";
import getPanel from "@salesforce/apex/PaymentLinkController.getPanel";
import createLink from "@salesforce/apex/PaymentLinkController.createLink";
import simulate from "@salesforce/apex/PaymentLinkController.simulate";

jest.mock(
  "@salesforce/apex/PaymentLinkController.getPanel",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentLinkController.createLink",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PaymentLinkController.simulate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

async function mount() {
  const el = createElement("c-kem-payment-links", { is: KemPaymentLinks });
  el.recordId = "a0I1";
  document.body.appendChild(el);
  await flush();
  return el;
}
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-payment-links", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("explains when online payments are off", async () => {
    getPanel.mockResolvedValue({
      mode: "Off",
      webhookConfigured: false,
      links: []
    });
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("Families pay at the branch");
    expect(button(el, "Create payment link")).toBeUndefined();
  });

  it("creates links and simulates the gateway in test mode", async () => {
    getPanel.mockResolvedValue({
      mode: "Test",
      webhookConfigured: false,
      links: [
        {
          Id: "a0L1",
          Name: "PL-000001",
          Amount__c: 1180,
          Status__c: "Active",
          Created_Via__c: "Portal"
        }
      ]
    });
    createLink.mockResolvedValue({ linkNumber: "PL-000002" });
    simulate.mockResolvedValue();
    const el = await mount();
    expect(el.shadowRoot.querySelector(".kem-badge_warning").textContent).toBe(
      "Active"
    );
    button(el, "Simulate payment").click();
    await flush();
    expect(simulate).toHaveBeenCalledWith({ linkId: "a0L1" });
    button(el, "Create payment link").click();
    await flush();
    expect(createLink).toHaveBeenCalledWith({ invoiceId: "a0I1" });
    expect(getPanel).toHaveBeenCalledTimes(3);
  });

  it("warns about a missing webhook secret in live mode and shows the checkout address", async () => {
    getPanel.mockResolvedValue({
      mode: "Live",
      webhookConfigured: false,
      links: []
    });
    createLink.mockResolvedValue({
      linkNumber: "PL-000003",
      checkoutUrl: "https://pay.example.com/c?ref=x"
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector(".slds-alert_warning")).not.toBeNull();
    button(el, "Create payment link").click();
    await flush();
    await flush();
    expect(el.shadowRoot.querySelector(".checkout").value).toBe(
      "https://pay.example.com/c?ref=x"
    );
  });

  it("stays hidden without access", async () => {
    getPanel.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'PaymentLinkController'."
      }
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });
});
