import { createElement } from "lwc";
import KemEnquiryPipeline from "c/kemEnquiryPipeline";
import getPipeline from "@salesforce/apex/EnquiryController.getPipeline";
import getBranches from "@salesforce/apex/EnquiryController.getBranches";
import updateStatus from "@salesforce/apex/EnquiryController.updateStatus";

jest.mock(
  "@salesforce/apex/EnquiryController.getPipeline",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnquiryController.getBranches",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnquiryController.updateStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const PIPELINE = [
  {
    status: "New",
    enquiries: [
      {
        Id: "00Q000000000001",
        Name: "Asha Rao",
        Status: "New",
        Follow_Up_Status__c: "Overdue",
        Next_Follow_Up__c: "2026-01-01T10:00:00.000Z",
        Possible_Duplicate__c: true,
        Enquiry_Channel__c: "Website",
        Interested_Course__r: { Name: "Mathematics" },
        Branch__r: { Name: "Bengaluru" },
        Owner: { Name: "Counsellor One" }
      }
    ]
  },
  {
    status: "Contacted",
    enquiries: [
      {
        Id: "00Q000000000002",
        Name: "Kiran Das",
        Status: "Contacted",
        Follow_Up_Status__c: "Due Today"
      }
    ]
  },
  { status: "Nurturing", enquiries: [] }
];

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-enquiry-pipeline", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function render() {
    const element = createElement("c-kem-enquiry-pipeline", {
      is: KemEnquiryPipeline
    });
    document.body.appendChild(element);
    getBranches.emit([{ Id: "a00000000000001", Name: "Bengaluru" }]);
    getPipeline.emit(PIPELINE);
    await flush();
    return element;
  }

  it("renders three stage columns with cards and KPIs", async () => {
    const element = await render();
    const columns = element.shadowRoot.querySelectorAll("section.column");
    expect(columns).toHaveLength(3);
    expect(element.shadowRoot.querySelectorAll("article.enquiry")).toHaveLength(
      2
    );
    const kpis = [
      ...element.shadowRoot.querySelectorAll(".kem-kpi__value")
    ].map((n) => n.textContent);
    expect(kpis).toEqual(["2", "1", "1", "1"]);
    expect(element.shadowRoot.textContent).toContain("Duplicate?");
    expect(element.shadowRoot.textContent).toContain("No enquiries");
  });

  it("filters cards by search term", async () => {
    const element = await render();
    const search = element.shadowRoot.querySelector(
      "lightning-input.toolbar-search"
    );
    search.value = "kiran";
    search.dispatchEvent(new CustomEvent("change"));
    await flush();
    const cards = element.shadowRoot.querySelectorAll("article.enquiry");
    expect(cards).toHaveLength(1);
    expect(cards[0].dataset.id).toBe("00Q000000000002");
  });

  it("moves an enquiry through the action menu and calls Apex", async () => {
    updateStatus.mockResolvedValue(undefined);
    const element = await render();
    const menu = element.shadowRoot.querySelector("lightning-button-menu");
    menu.dispatchEvent(
      new CustomEvent("select", { detail: { value: "move:Contacted" } })
    );
    await flush();
    expect(updateStatus).toHaveBeenCalledWith({
      leadId: "00Q000000000001",
      status: "Contacted",
      lostReason: null
    });
  });

  it("shows an error banner when the pipeline cannot load", async () => {
    const element = createElement("c-kem-enquiry-pipeline", {
      is: KemEnquiryPipeline
    });
    document.body.appendChild(element);
    getPipeline.error({ message: "No access" });
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_error")
    ).not.toBeNull();
  });
});
