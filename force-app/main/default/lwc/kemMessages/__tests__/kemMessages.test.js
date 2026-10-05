import { createElement } from "lwc";
import KemMessages from "c/kemMessages";
import getTimeline from "@salesforce/apex/MessageController.getTimeline";
import setEmailOptOut from "@salesforce/apex/MessageController.setEmailOptOut";
import MessageModal from "c/kemMessageModal";

jest.mock(
  "@salesforce/apex/MessageController.getTimeline",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MessageController.setEmailOptOut",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemMessageModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const TIMELINE = {
  emailLive: false,
  canManageConsent: true,
  recipients: [
    {
      contactId: "003A",
      name: "Kabir Rao",
      role: "Learner",
      email: null,
      optedOut: false,
      feePayer: false
    },
    {
      contactId: "003B",
      name: "Meera Rao",
      role: "Mother",
      email: "meera@example.com",
      optedOut: false,
      feePayer: true
    }
  ],
  messages: [
    {
      Id: "a0M1",
      Channel__c: "Email",
      Event__c: "Invoice_Issued",
      Subject__c: "Invoice BLR-000005 for Kabir",
      Body__c: "Dear Meera, ...",
      Status__c: "Not Sent",
      Status_Detail__c: "Email delivery is switched off",
      CreatedDate: "2026-10-05T10:00:00.000Z",
      Recipient__r: { Name: "Meera Rao" }
    },
    {
      Id: "a0M2",
      Channel__c: "Portal",
      Event__c: "Invoice_Issued",
      Subject__c: "Invoice BLR-000005 for Kabir",
      Body__c: "Dear Meera, ...",
      Status__c: "Delivered",
      Sent_On__c: "2026-10-05T10:00:00.000Z",
      Recipient__r: { Name: "Meera Rao" }
    }
  ]
};

async function mount() {
  const element = createElement("c-kem-messages", { is: KemMessages });
  element.recordId = "001A";
  document.body.appendChild(element);
  await flush();
  return element;
}

describe("c-kem-messages", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows recipients, consent, the delivery banner and filters", async () => {
    getTimeline.mockResolvedValue(TIMELINE);
    const element = await mount();
    const root = element.shadowRoot;
    expect(root.querySelector(".banner")).toBeTruthy();
    expect(root.querySelectorAll(".person")).toHaveLength(2);
    expect(root.textContent).toContain("fee payer");
    expect(root.querySelectorAll(".item")).toHaveLength(2);
    root.querySelector('button[data-value="attention"]').click();
    await flush();
    expect(root.querySelectorAll(".item")).toHaveLength(1);
    root.querySelector(".item-head").click();
    await flush();
    expect(root.querySelector(".body").textContent).toContain("Dear Meera");
  });

  it("records an email opt-out and opens the composer", async () => {
    getTimeline.mockResolvedValue(TIMELINE);
    setEmailOptOut.mockResolvedValue(undefined);
    MessageModal.open.mockResolvedValue(true);
    const element = await mount();
    const buttons = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ];
    buttons.find((b) => b.label === "Opt out").click();
    await flush();
    expect(setEmailOptOut).toHaveBeenCalledWith({
      learnerAccountId: "001A",
      contactId: "003B",
      optedOut: true
    });
    buttons.find((b) => b.label === "New message").click();
    await flush();
    expect(MessageModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ learnerAccountId: "001A", emailLive: false })
    );
  });

  it("shows load errors", async () => {
    getTimeline.mockRejectedValue({
      body: { message: "Learner not found or not accessible." }
    });
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("not accessible");
  });
});
