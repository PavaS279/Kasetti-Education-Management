import { createElement } from "lwc";
import KemForecast from "c/kemForecast";
import getForecast from "@salesforce/apex/ForecastController.getForecast";
import explainForecast from "@salesforce/apex/ForecastController.explainForecast";
import getBranches from "@salesforce/apex/AnalyticsController.getBranches";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import review from "@salesforce/apex/AiController.review";

jest.mock(
  "@salesforce/apex/ForecastController.getForecast",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ForecastController.explainForecast",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AnalyticsController.getBranches",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.isAvailable",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function series(metric, values, future, accuracy, mape) {
  const points = values.map((v, i) => ({
    key: `2026-0${i + 1}`,
    label: `M${i + 1}`,
    actual: v,
    isFuture: false
  }));
  future.forEach((f, i) => {
    points.push({
      key: `F${i}`,
      label: `F${i + 1}`,
      forecast: f,
      low: f - 1,
      high: f + 2,
      isFuture: true
    });
  });
  return {
    metric,
    method: "Average",
    mape,
    accuracy,
    historyMonths: values.length,
    points,
    nextTotal: future.reduce((a, b) => a + b, 0),
    lastTotal: 3,
    change: 0
  };
}

const FORECAST = {
  horizon: 3,
  showEnrolments: true,
  showFinance: true,
  enrolments: series(
    "New enrolments",
    [1, 1, 1, 1, 1, 1],
    [1, 1, 1],
    "Good",
    0
  ),
  pipeline: [
    {
      stage: "Open enquiries",
      count: 4,
      rate: 21,
      assumed: true,
      expected: 0.8
    },
    {
      stage: "Offers awaiting a reply",
      count: 2,
      rate: 80,
      assumed: false,
      expected: 1.6
    }
  ],
  pipelineExpected: 2.4,
  seats: [
    {
      course: "Maths",
      classes: 1,
      freeSeats: 1,
      demand: 3,
      gap: -2,
      status: "Short"
    },
    {
      course: "Coding",
      classes: 2,
      freeSeats: 10,
      demand: 1,
      gap: 9,
      status: "OK"
    }
  ],
  revenue: series(
    "Invoiced",
    [1000, 2000],
    [1500, 1500, 1500],
    "Not enough history",
    null
  ),
  collections: series(
    "Collected",
    [900, 1800],
    [1400, 1400, 1400],
    "Not enough history",
    null
  ),
  cash: [
    {
      key: "a",
      label: "Oct 26",
      dueFromOpen: 500,
      committedBilling: 1000,
      expectedCash: 1350
    },
    {
      key: "b",
      label: "Nov 26",
      dueFromOpen: 0,
      committedBilling: 1000,
      expectedCash: 900
    }
  ],
  collectionRate: 90,
  openReceivables: 500,
  notes: [
    "Maths: about 3 new learners expected but 1 free seats: open another class."
  ]
};

async function mount(recordId) {
  const el = createElement("c-kem-forecast", { is: KemForecast });
  if (recordId) {
    el.recordId = recordId;
  }
  document.body.appendChild(el);
  await flush();
  await flush();
  return el;
}

describe("c-kem-forecast", () => {
  beforeEach(() => {
    getBranches.mockResolvedValue([{ label: "Central", value: "a01" }]);
    getForecast.mockResolvedValue(FORECAST);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows tiles, charts with accuracy, pipeline, seats and cash", async () => {
    const el = await mount();
    expect(getForecast).toHaveBeenCalledWith({ branchId: null, horizon: 3 });
    const tiles = el.shadowRoot.querySelectorAll(".tile");
    expect(tiles).toHaveLength(6);
    expect(tiles[0].textContent).toContain("3");
    expect(tiles[2].className).toContain("tile_warn");
    expect(tiles[2].textContent).toContain("open another class");
    expect(el.shadowRoot.querySelectorAll("path.bar_future")).toHaveLength(6);
    expect(el.shadowRoot.querySelectorAll("line.divider")).toHaveLength(2);
    const chips = [...el.shadowRoot.querySelectorAll(".chip")].map(
      (c) => c.textContent
    );
    expect(chips).toEqual(
      expect.arrayContaining(["Good", "Not enough history", "Short", "OK"])
    );
    expect(el.shadowRoot.textContent).toContain("21% (assumed)");
    expect(el.shadowRoot.textContent).toContain("open another class.");
    expect(el.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(6);
    expect(el.shadowRoot.querySelector("lightning-combobox")).not.toBeNull();
  });

  it("reloads for another branch and horizon", async () => {
    const el = await mount();
    const combo = el.shadowRoot.querySelector("lightning-combobox");
    combo.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a01" } })
    );
    await flush();
    expect(getForecast).toHaveBeenLastCalledWith({
      branchId: "a01",
      horizon: 3
    });
    el.shadowRoot
      .querySelector("lightning-radio-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "6" } }));
    await flush();
    expect(getForecast).toHaveBeenLastCalledWith({
      branchId: "a01",
      horizon: 6
    });
  });

  it("uses the branch of a branch page and hides the picker", async () => {
    const el = await mount("a02");
    expect(getForecast).toHaveBeenCalledWith({ branchId: "a02", horizon: 3 });
    expect(getBranches).not.toHaveBeenCalled();
    expect(el.shadowRoot.querySelector("lightning-combobox")).toBeNull();
  });

  it("explains with Einstein and records feedback", async () => {
    explainForecast.mockResolvedValue({
      ok: true,
      text: "Enrolments are steady.\n\nOpen another Maths class.",
      interactionId: "a0X1"
    });
    review.mockResolvedValue();
    const el = await mount();
    isAvailable.emit(true);
    await flush();
    const button = [...el.shadowRoot.querySelectorAll("lightning-button")].find(
      (b) => b.label === "Explain with Einstein"
    );
    button.click();
    await flush();
    await flush();
    expect(el.shadowRoot.querySelectorAll(".narrative p")).toHaveLength(2);
    el.shadowRoot.querySelector('[data-helpful="true"]').click();
    await flush();
    expect(review).toHaveBeenCalledWith(
      expect.objectContaining({ interactionId: "a0X1", outcome: "Accepted" })
    );
    expect(el.shadowRoot.textContent).toContain("Thanks for the feedback");
  });

  it("hides itself without access and shows other errors", async () => {
    getForecast.mockRejectedValue({
      body: { message: "You do not have access to this." }
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
    document.body.removeChild(el);
    getForecast.mockRejectedValue({ body: { message: "Boom" } });
    const other = await mount();
    expect(other.shadowRoot.textContent).toContain("Boom");
  });
});
