import { createElement } from "lwc";
import KemAiProgress from "c/kemAiProgress";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import learnerProgress from "@salesforce/apex/AiController.learnerProgress";
import review from "@salesforce/apex/AiController.review";
import getTimeline from "@salesforce/apex/MessageController.getTimeline";
import sendMessage from "@salesforce/apex/MessageController.sendMessage";

jest.mock(
  "@salesforce/apex/AiController.isAvailable",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/AiController.learnerProgress",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MessageController.getTimeline",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MessageController.sendMessage",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => new Promise((resolve) => process.nextTick(resolve));
const RESULT = {
  ok: true,
  text: "Dear Rohit,\nThank you.",
  interactionId: "a0X1",
  model: "sfdc_ai__DefaultGPT4Omni",
  latencyMs: 800,
  feature: "X"
};

describe("c-kem-ai-progress", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("drafts, defaults to the fee payer and sends", async () => {
    learnerProgress.mockResolvedValue(RESULT);
    getTimeline.mockResolvedValue({
      recipients: [
        { contactId: "003L", name: "Ananya", role: "Learner", feePayer: false },
        { contactId: "003F", name: "Rohit", role: "Father", feePayer: true }
      ]
    });
    sendMessage.mockResolvedValue(["a0M1"]);
    review.mockResolvedValue();
    const el = createElement("c-kem-ai-progress", { is: KemAiProgress });
    el.recordId = "001A";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const combo = el.shadowRoot.querySelector("lightning-combobox");
    expect(combo.value).toBe("003F");
    expect(combo.options[1].label).toBe("Rohit (Father, fee payer)");
    el.shadowRoot.querySelector("c-kem-ai-draft").dispatchEvent(
      new CustomEvent("use", {
        detail: {
          text: "Ananya is doing well.",
          interactionId: "a0X1",
          rating: 5
        }
      })
    );
    await flush();
    await flush();
    expect(sendMessage).toHaveBeenCalledWith({
      request: {
        learnerAccountId: "001A",
        recipientId: "003F",
        channel: "Both",
        subject: "Progress update",
        body: "Ananya is doing well."
      }
    });
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({
        interactionId: "a0X1",
        outcome: "Edited",
        rating: 5
      })
    );
  });

  it("needs a recipient and reports errors", async () => {
    learnerProgress.mockResolvedValue(RESULT);
    getTimeline.mockResolvedValue({ recipients: [] });
    const el = createElement("c-kem-ai-progress", { is: KemAiProgress });
    el.recordId = "001A";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    el.shadowRoot
      .querySelector("c-kem-ai-draft")
      .dispatchEvent(new CustomEvent("use", { detail: { text: "x" } }));
    await flush();
    expect(
      el.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("Choose who receives");
    el.shadowRoot
      .querySelector("c-kem-ai-draft")
      .dispatchEvent(new CustomEvent("discard"));
    await flush();
    expect(el.shadowRoot.querySelector("c-kem-ai-draft")).toBeNull();
  });
});
