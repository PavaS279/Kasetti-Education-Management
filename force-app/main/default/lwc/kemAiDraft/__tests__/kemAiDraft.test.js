import { createElement } from "lwc";
import KemAiDraft from "c/kemAiDraft";
import review from "@salesforce/apex/AiController.review";

jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => new Promise((resolve) => process.nextTick(resolve));

function mount(props) {
  const el = createElement("c-kem-ai-draft", { is: KemAiDraft });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}
const button = (el, label) =>
  [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-ai-draft", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("emits the edited text with rating when used", async () => {
    const el = mount({
      result: {
        text: "Hello there",
        interactionId: "a0X1",
        model: "sfdc_ai__DefaultGPT4Omni",
        latencyMs: 1200
      },
      editable: true,
      useLabel: "Send"
    });
    await flush();
    expect(el.shadowRoot.textContent).toContain("GPT4Omni · 1.2 s");
    const handler = jest.fn();
    el.addEventListener("use", handler);
    const area = el.shadowRoot.querySelector("lightning-textarea");
    area.value = "Hello there, friend";
    area.dispatchEvent(new CustomEvent("change"));
    el.shadowRoot.querySelectorAll("button.star")[3].click();
    await flush();
    expect(el.shadowRoot.querySelectorAll(".star_on")).toHaveLength(4);
    button(el, "Send").click();
    expect(handler.mock.calls[0][0].detail).toEqual({
      text: "Hello there, friend",
      interactionId: "a0X1",
      edited: true,
      rating: 4
    });
  });

  it("records a rejection on discard and can regenerate", async () => {
    review.mockResolvedValue();
    const el = mount({ result: { text: "Draft", interactionId: "a0X2" } });
    await flush();
    const regen = jest.fn();
    const discard = jest.fn();
    el.addEventListener("regenerate", regen);
    el.addEventListener("discard", discard);
    button(el, "Regenerate").click();
    expect(regen).toHaveBeenCalled();
    button(el, "Discard").click();
    await flush();
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({ interactionId: "a0X2", outcome: "Rejected" })
    );
    expect(discard).toHaveBeenCalled();
  });

  it("renders nothing without a result", () => {
    const el = mount({});
    expect(el.shadowRoot.querySelector(".draft")).toBeNull();
  });
});
