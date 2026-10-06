import { createElement } from "lwc";
import KemAiAsk from "c/kemAiAsk";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import askPolicy from "@salesforce/apex/AiController.askPolicy";
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
  "@salesforce/apex/AiController.askPolicy",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => new Promise((resolve) => process.nextTick(resolve));
async function mount() {
  const el = createElement("c-kem-ai-ask", { is: KemAiAsk });
  document.body.appendChild(el);
  isAvailable.emit(true);
  await flush();
  return el;
}

describe("c-kem-ai-ask", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("answers with sources and records feedback", async () => {
    askPolicy.mockResolvedValue({
      answer: "Someone other than the requester must approve it.",
      sources: ["Refunds and credit notes"],
      confident: true,
      interactionId: "a0X1"
    });
    review.mockResolvedValue();
    const el = await mount();
    expect(el.shadowRoot.querySelectorAll(".example")).toHaveLength(3);
    el.shadowRoot.querySelector(".example").click();
    await flush();
    expect(askPolicy).toHaveBeenCalledWith({
      question: "Who can approve a refund I requested?"
    });
    expect(el.shadowRoot.querySelector(".source").textContent).toBe(
      "Refunds and credit notes"
    );
    expect(el.shadowRoot.querySelector(".kem-badge_success")).not.toBeNull();
    el.shadowRoot
      .querySelector('lightning-button-icon[data-helpful="false"]')
      .click();
    await flush();
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({
        outcome: "Rejected",
        feedback: "Who can approve a refund I requested?"
      })
    );
  });

  it("asks on Enter, flags unknown answers and errors", async () => {
    askPolicy
      .mockResolvedValueOnce({
        answer: "I could not find this.",
        sources: [],
        confident: false
      })
      .mockRejectedValueOnce({
        body: { message: "Ask a question of a few words." }
      });
    const el = await mount();
    const input = el.shadowRoot.querySelector("lightning-input");
    input.value = "What is the hostel curfew?";
    input.dispatchEvent(new CustomEvent("change"));
    input.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter" }));
    await flush();
    expect(
      el.shadowRoot.querySelector(".kem-badge_warning").textContent
    ).toContain("Not found");
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(el.shadowRoot.querySelector(".slds-alert_error")).not.toBeNull();
  });
});
