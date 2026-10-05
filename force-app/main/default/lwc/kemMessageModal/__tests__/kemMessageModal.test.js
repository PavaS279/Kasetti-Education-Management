import { createElement } from "lwc";
import KemMessageModal from "c/kemMessageModal";
import sendMessage from "@salesforce/apex/MessageController.sendMessage";

jest.mock(
  "@salesforce/apex/MessageController.sendMessage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const RECIPIENTS = [
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
    optedOut: true,
    feePayer: true
  }
];

describe("c-kem-message-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("defaults to the fee payer, warns about consent and sends", async () => {
    sendMessage.mockResolvedValue(["a0M1", "a0M2"]);
    const element = createElement("c-kem-message-modal", {
      is: KemMessageModal
    });
    element.learnerAccountId = "001A";
    element.recipients = RECIPIENTS;
    element.emailLive = true;
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector("lightning-combobox").value).toBe("003B");
    expect(root.querySelector(".warning").textContent).toContain("opted out");
    const send = () =>
      [...root.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Send"
      );
    expect(send().disabled).toBe(true);
    const subject = root.querySelector("lightning-input");
    subject.value = "Meeting";
    subject.dispatchEvent(new CustomEvent("change"));
    const body = root.querySelector("lightning-textarea");
    body.value = "See you Friday";
    body.dispatchEvent(new CustomEvent("change"));
    await flush();
    send().click();
    await flush();
    expect(sendMessage).toHaveBeenCalledWith({
      request: {
        learnerAccountId: "001A",
        recipientId: "003B",
        channel: "Both",
        subject: "Meeting",
        body: "See you Friday"
      }
    });
  });

  it("explains when delivery is off and hides the warning for portal only", async () => {
    const element = createElement("c-kem-message-modal", {
      is: KemMessageModal
    });
    element.learnerAccountId = "001A";
    element.recipients = [
      RECIPIENTS[1],
      { ...RECIPIENTS[0], feePayer: false }
    ].map((r) => ({
      ...r,
      optedOut: false,
      email: "x@example.com"
    }));
    element.emailLive = false;
    document.body.appendChild(element);
    await flush();
    const root = element.shadowRoot;
    expect(root.querySelector(".warning").textContent).toContain(
      "switched off"
    );
    root
      .querySelectorAll("lightning-combobox")[1]
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: "Portal" } })
      );
    await flush();
    expect(root.querySelector(".warning")).toBeNull();
  });
});
