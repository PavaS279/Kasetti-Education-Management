import { createElement } from "lwc";
import KemAiEnquiryReply from "c/kemAiEnquiryReply";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import draftEnquiryReply from "@salesforce/apex/AiController.draftEnquiryReply";
import recordEnquiryReply from "@salesforce/apex/AiController.recordEnquiryReply";

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
  "@salesforce/apex/AiController.draftEnquiryReply",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.recordEnquiryReply",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
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

async function mount() {
  const el = createElement("c-kem-ai-enquiry-reply", { is: KemAiEnquiryReply });
  el.recordId = "00Q1";
  document.body.appendChild(el);
  isAvailable.emit(true);
  await flush();
  return el;
}

describe("c-kem-ai-enquiry-reply", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("drafts, then copies and records the reply", async () => {
    draftEnquiryReply.mockResolvedValue(RESULT);
    recordEnquiryReply.mockResolvedValue();
    Object.assign(navigator, {
      clipboard: { writeText: jest.fn().mockResolvedValue() }
    });
    const el = await mount();
    const note = el.shadowRoot.querySelector("lightning-input");
    note.value = "Mention the Saturday class";
    note.dispatchEvent(new CustomEvent("change"));
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(draftEnquiryReply).toHaveBeenCalledWith({
      leadId: "00Q1",
      note: "Mention the Saturday class"
    });
    const draft = el.shadowRoot.querySelector("c-kem-ai-draft");
    draft.dispatchEvent(
      new CustomEvent("use", {
        detail: { text: "Dear Rohit", interactionId: "a0X1" }
      })
    );
    await flush();
    await flush();
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith("Dear Rohit");
    expect(recordEnquiryReply).toHaveBeenCalledWith({
      leadId: "00Q1",
      reply: "Dear Rohit",
      interactionId: "a0X1"
    });
    expect(el.shadowRoot.querySelector("c-kem-ai-draft")).toBeNull();
  });

  it("shows errors, discards and hides when AI is unavailable", async () => {
    draftEnquiryReply
      .mockRejectedValueOnce({
        body: { message: "AI assistants are switched off for the institution." }
      })
      .mockResolvedValueOnce(RESULT);
    const el = await mount();
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(
      el.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("switched off");
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    el.shadowRoot
      .querySelector("c-kem-ai-draft")
      .dispatchEvent(new CustomEvent("discard"));
    await flush();
    expect(el.shadowRoot.querySelector("c-kem-ai-draft")).toBeNull();
    isAvailable.emit(false);
    await flush();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });
});
