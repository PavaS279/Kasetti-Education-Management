import { createElement } from "lwc";
import KemAiConsole from "c/kemAiConsole";
import getConsole from "@salesforce/apex/AiController.getConsole";
import runEvaluation from "@salesforce/apex/AiController.runEvaluation";

jest.mock(
  "@salesforce/apex/AiController.getConsole",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.runEvaluation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => new Promise((resolve) => process.nextTick(resolve));

function data(overrides = {}) {
  return {
    enabled: true,
    model: "sfdc_ai__DefaultGPT4Omni",
    disabledFeatures: "",
    canUse: true,
    isAdmin: true,
    users: 3,
    agentCalls: 2,
    totals: {
      calls: 20,
      failed: 1,
      reviewed: 15,
      accepted: 8,
      edited: 5,
      rejected: 2,
      acceptanceRate: 86.7,
      minutesSaved: 42.5,
      averageLatencyMs: 1500
    },
    features: [
      {
        feature: "Enquiry Reply",
        calls: 10,
        failed: 0,
        reviewed: 8,
        accepted: 4,
        edited: 3,
        rejected: 1,
        acceptanceRate: 87.5,
        averageEdit: 12.3,
        averageRating: 4.5,
        minutesSaved: 25
      }
    ],
    evaluation: {
      runLabel: "Run 2026-10-06 10:00",
      cases: 7,
      passed: 7,
      averageScore: 100,
      averageLatencyMs: 1200
    },
    ...overrides
  };
}

async function mount() {
  const el = createElement("c-kem-ai-console", { is: KemAiConsole });
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-kem-ai-console", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows measured benefit, features and evaluation", async () => {
    getConsole.mockResolvedValue(data());
    runEvaluation.mockResolvedValue({ cases: 7, passed: 6 });
    const el = await mount();
    const tiles = el.shadowRoot.querySelectorAll(".tile");
    expect(tiles).toHaveLength(7);
    expect(tiles[2].textContent).toContain("2");
    expect(tiles[3].textContent).toContain("86.7%");
    expect(tiles[4].textContent).toContain("42.5");
    expect(el.shadowRoot.querySelector(".tile_warn")).not.toBeNull();
    const cells = el.shadowRoot.querySelectorAll("tbody td");
    expect(cells[0].textContent).toBe("Enquiry Reply");
    expect(cells[5].textContent).toBe("2");
    expect(el.shadowRoot.textContent).toContain("7 of 7 cases passed");
    el.shadowRoot
      .querySelector("lightning-combobox")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "7" } }));
    await flush();
    expect(getConsole).toHaveBeenLastCalledWith({ days: 7 });
    el.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(runEvaluation).toHaveBeenCalled();
  });

  it("shows an empty period, switched-off state and hides for users without AI", async () => {
    getConsole.mockResolvedValue(
      data({ enabled: false, features: [], evaluation: null, isAdmin: true })
    );
    const el = await mount();
    expect(el.shadowRoot.querySelector(".kem-badge_danger").textContent).toBe(
      "AI switched off"
    );
    expect(el.shadowRoot.textContent).toContain("No AI requests");
    expect(el.shadowRoot.textContent).toContain("Not run yet");
    getConsole.mockResolvedValue(data({ canUse: false, isAdmin: false }));
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
