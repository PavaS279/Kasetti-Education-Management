import { createElement } from "lwc";
import KemApplicationWorkbench from "c/kemApplicationWorkbench";
import getApplication from "@salesforce/apex/ApplicationController.getApplication";
import performAction from "@salesforce/apex/ApplicationController.performAction";
import updateChecklistItem from "@salesforce/apex/ApplicationController.updateChecklistItem";

jest.mock(
  "@salesforce/apex/ApplicationController.getApplication",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApplicationController.performAction",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApplicationController.decide",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApplicationController.updateChecklistItem",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ApplicationController.addChecklistItem",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const VIEW = {
  canOverrideEligibility: true,
  requiredOpen: 1,
  application: {
    Id: "0iT000000000001",
    Name: "IA-0001",
    Status: "In Review",
    AccountId: "001000000000001",
    Account: { Name: "Ananya Sharma" },
    Learning_Course__r: { Name: "Mathematics" },
    Branch__r: { Name: "Bengaluru" },
    Eligibility_Status__c: "Not Eligible",
    Eligibility_Notes__c: "Age 15; course range 8–12.",
    Offer_Status__c: "Not Offered"
  },
  checklist: [
    {
      id: "0dI000000000001",
      name: "Birth Certificate",
      status: "Accepted",
      required: true,
      fileCount: 1
    },
    {
      id: "0dI000000000002",
      name: "Address Proof",
      status: "New",
      required: true,
      fileCount: 0
    },
    {
      id: "0dI000000000003",
      name: "Photo",
      status: "New",
      required: false,
      fileCount: 0
    }
  ]
};

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-application-workbench", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function render() {
    const element = createElement("c-kem-application-workbench", {
      is: KemApplicationWorkbench
    });
    element.recordId = "0iT000000000001";
    document.body.appendChild(element);
    getApplication.emit(VIEW);
    await flush();
    return element;
  }

  it("renders progress, checklist, eligibility, and stage actions", async () => {
    const element = await render();
    expect(element.shadowRoot.querySelector(".ring-value").textContent).toBe(
      "1/2"
    );
    expect(element.shadowRoot.querySelectorAll("li.item")).toHaveLength(3);
    const labels = [
      ...element.shadowRoot.querySelectorAll(".hero-actions lightning-button")
    ].map((b) => b.label);
    expect(labels).toEqual(["Return", "Ready for decision", "Withdraw"]);
    expect(element.shadowRoot.textContent).toContain("Not Eligible");
    const override = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Override eligibility");
    expect(override).toBeTruthy();
  });

  it("calls Apex for a stage action and a checklist acceptance", async () => {
    performAction.mockResolvedValue(undefined);
    updateChecklistItem.mockResolvedValue(undefined);
    const element = await render();
    const ready = [
      ...element.shadowRoot.querySelectorAll(".hero-actions lightning-button")
    ].find((b) => b.label === "Ready for decision");
    ready.click();
    await flush();
    expect(performAction).toHaveBeenCalledWith({
      applicationId: "0iT000000000001",
      action: "ready",
      reason: null
    });
    const accept = element.shadowRoot.querySelector(
      'lightning-button-icon[data-id="0dI000000000002"][data-status="Accepted"]'
    );
    accept.click();
    await flush();
    expect(updateChecklistItem).toHaveBeenCalledWith({
      itemId: "0dI000000000002",
      status: "Accepted",
      rejectReason: null
    });
  });
});
