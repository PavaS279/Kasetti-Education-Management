import { createElement } from "lwc";
import KemTransportDesk from "c/kemTransportDesk";
import getRoutes from "@salesforce/apex/TransportController.getRoutes";
import getRoute from "@salesforce/apex/TransportController.getRoute";
import searchLearners from "@salesforce/apex/TransportController.searchLearners";
import assign from "@salesforce/apex/TransportController.assign";
import changeStop from "@salesforce/apex/TransportController.changeStop";
import endAssignment from "@salesforce/apex/TransportController.endAssignment";
import notifyRoute from "@salesforce/apex/TransportController.notifyRoute";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/TransportController.getRoutes",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.getRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.searchLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.assign",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.changeStop",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.endAssignment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransportController.notifyRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => process.nextTick(resolve));
  }
};

const ROUTES = [
  {
    routeId: "r1",
    name: "Route 1",
    code: "R1",
    vehicle: "KA01",
    driver: "Ravi",
    capacity: 2,
    riders: 2,
    fillRate: 100,
    monthlyFee: 1200,
    stops: 2,
    active: true
  },
  {
    routeId: "r2",
    name: "Route 2",
    code: "R2",
    capacity: 10,
    riders: 1,
    fillRate: 10,
    monthlyFee: 900,
    stops: 1,
    active: true
  }
];
const DETAIL = {
  canManage: true,
  route: ROUTES[0],
  stops: [
    {
      stopId: "s1",
      name: "Lake View",
      sequence: 1,
      pickupTime: "07:20",
      dropTime: "15:40",
      riders: [
        {
          assignmentId: "a1",
          learner: "Riya",
          direction: "Both ways",
          guardian: "Meena",
          guardianPhone: "+91 98"
        }
      ]
    },
    {
      stopId: "s2",
      name: "Market",
      sequence: 2,
      pickupTime: "07:35",
      riders: []
    }
  ]
};

async function mount() {
  const el = createElement("c-kem-transport-desk", { is: KemTransportDesk });
  el.recordId = "b1";
  document.body.appendChild(el);
  await flush();
  return el;
}

function button(el, label) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );
}

describe("c-kem-transport-desk", () => {
  beforeEach(() => {
    getRoutes.mockResolvedValue(ROUTES);
    getRoute.mockResolvedValue(DETAIL);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists routes and shows the manifest of the first", async () => {
    const el = await mount();
    expect(getRoutes).toHaveBeenCalledWith({ branchId: "b1" });
    expect(getRoute).toHaveBeenCalledWith({ routeId: "r1" });
    expect(el.shadowRoot.querySelectorAll(".route")).toHaveLength(2);
    expect(el.shadowRoot.querySelector(".bar-fill_full")).not.toBeNull();
    expect(el.shadowRoot.querySelectorAll(".stop")).toHaveLength(2);
    expect(el.shadowRoot.querySelector(".rider").textContent).toContain(
      "Meena"
    );
    expect(el.shadowRoot.textContent).toContain("pick-up 07:20 · drop 15:40");
    el.shadowRoot.querySelectorAll(".route")[1].click();
    await flush();
    expect(getRoute).toHaveBeenLastCalledWith({ routeId: "r2" });
  });

  it("finds a learner and adds them to the route", async () => {
    searchLearners.mockResolvedValue([{ learnerAccountId: "l1", name: "Sam" }]);
    assign.mockResolvedValue("a2");
    const el = await mount();
    button(el, "Add learner").click();
    await flush();
    const search = el.shadowRoot.querySelector(".form lightning-input");
    search.value = "Sa";
    search.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(searchLearners).toHaveBeenCalledWith({ routeId: "r1", term: "Sa" });
    const pick = el.shadowRoot.querySelector(
      'lightning-combobox[data-field="learnerId"]'
    );
    pick.dispatchEvent(new CustomEvent("change", { detail: { value: "l1" } }));
    await flush();
    button(el, "Add to route").click();
    await flush();
    expect(assign).toHaveBeenCalledWith({
      request: expect.objectContaining({
        learnerAccountId: "l1",
        routeId: "r1",
        stopId: "s1",
        direction: "Both ways",
        chargeFee: true
      })
    });
    expect(getRoutes).toHaveBeenCalledTimes(2);
  });

  it("changes a stop, ends transport and messages families", async () => {
    changeStop.mockResolvedValue();
    endAssignment.mockResolvedValue();
    notifyRoute.mockResolvedValue(1);
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    const el = await mount();
    el.shadowRoot
      .querySelector("lightning-combobox.stop-pick")
      .dispatchEvent(new CustomEvent("change", { detail: { value: "s2" } }));
    await flush();
    expect(changeStop).toHaveBeenCalledWith({
      assignmentId: "a1",
      stopId: "s2"
    });
    el.shadowRoot.querySelector('lightning-button-icon[data-id="a1"]').click();
    await flush();
    expect(endAssignment).toHaveBeenCalledWith(
      expect.objectContaining({ assignmentId: "a1" })
    );
    button(el, "Message families").click();
    await flush();
    const text = el.shadowRoot.querySelector("lightning-textarea");
    text.value = "Bus is late today";
    text.dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el, "Send").click();
    await flush();
    expect(notifyRoute).toHaveBeenCalledWith({
      routeId: "r1",
      message: "Bus is late today"
    });
  });

  it("hides management for read-only users and shows an empty state", async () => {
    getRoute.mockResolvedValue({ ...DETAIL, canManage: false });
    const el = await mount();
    expect(button(el, "Add learner")).toBeUndefined();
    expect(
      el.shadowRoot.querySelector("lightning-combobox.stop-pick")
    ).toBeNull();
    document.body.removeChild(el);
    getRoutes.mockResolvedValue([]);
    const empty = await mount();
    expect(empty.shadowRoot.textContent).toContain("No routes yet");
  });

  it("hides itself without access", async () => {
    getRoutes.mockRejectedValue({
      body: { message: "You do not have access to the Apex class" }
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });
});
