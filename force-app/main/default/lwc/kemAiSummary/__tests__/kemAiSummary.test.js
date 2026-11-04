import { createElement } from "lwc";
import KemAiSummary from "c/kemAiSummary";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import summarise from "@salesforce/apex/AiController.summarise";
import review from "@salesforce/apex/AiController.review";

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
  "@salesforce/apex/AiController.summarise",
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

describe("c-kem-ai-summary", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("summarises as bullets and records feedback", async () => {
    summarise.mockResolvedValue({
      ...RESULT,
      text: "- Contacted twice\n- Trial on Saturday\n\n* Call back today"
    });
    review.mockResolvedValue();
    const el = createElement("c-kem-ai-summary", { is: KemAiSummary });
    el.recordId = "00Q1";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    const items = el.shadowRoot.querySelectorAll(".bullets li");
    expect(items).toHaveLength(3);
    expect(items[2].textContent).toBe("Call back today");
    el.shadowRoot
      .querySelector('lightning-button-icon[data-helpful="true"]')
      .click();
    await flush();
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({ outcome: "Accepted", rating: 5 })
    );
    expect(el.shadowRoot.textContent).toContain("Thanks for the feedback");
  });

  it("shows an error for unsupported records", async () => {
    summarise.mockRejectedValue({
      body: {
        message: "AI summaries are not available for this kind of record."
      }
    });
    const el = createElement("c-kem-ai-summary", { is: KemAiSummary });
    el.recordId = "a0Z1";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(
      el.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("not available");
  });
});
