import { createElement } from "lwc";
import KemCoursePricing from "c/kemCoursePricing";
import getCoursePrices from "@salesforce/apex/PricingController.getCoursePrices";
import getQuote from "@salesforce/apex/PricingController.getQuote";
import getBranches from "@salesforce/apex/EnquiryController.getBranches";

jest.mock(
  "@salesforce/apex/PricingController.getCoursePrices",
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
  "@salesforce/apex/PricingController.getQuote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PricingController.endPrice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const PRICES = [
  {
    Id: "a01000000000001",
    Name: "PRC-00001",
    Fee_Type__c: "Tuition",
    Billing_Frequency__c: "Monthly",
    Amount__c: 3500,
    Active__c: true,
    Effective_From__c: "2020-01-01"
  },
  {
    Id: "a01000000000002",
    Name: "PRC-00002",
    Fee_Type__c: "Admission",
    Billing_Frequency__c: "One-time",
    Amount__c: 2000,
    Active__c: true,
    Effective_From__c: "2999-01-01"
  }
];

describe("c-kem-course-pricing", () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("lists prices with state and runs a debounced quote", async () => {
    getQuote.mockResolvedValue({
      lines: [
        {
          feePriceId: "a01000000000001",
          feeType: "Tuition",
          frequency: "Monthly",
          unitAmount: 3500,
          discountAmount: 350,
          taxAmount: 0,
          total: 3150
        }
      ],
      subtotal: 3500,
      discountTotal: 350,
      taxTotal: 0,
      grandTotal: 3150,
      approvalRequired: false,
      warnings: []
    });
    const element = createElement("c-kem-course-pricing", {
      is: KemCoursePricing
    });
    element.recordId = "0kE000000000001";
    document.body.appendChild(element);
    getBranches.emit([]);
    getCoursePrices.emit(PRICES);
    await Promise.resolve();
    const states = [
      ...element.shadowRoot.querySelectorAll(".price .kem-badge:first-child")
    ].map((n) => n.textContent);
    expect(states).toEqual(["Active", "Scheduled"]);
    expect(
      element.shadowRoot.querySelector(".kem-kpi__value").textContent
    ).toBe("1");

    jest.runAllTimers();
    await Promise.resolve();
    await Promise.resolve();
    expect(getQuote).toHaveBeenCalledWith({
      request: expect.objectContaining({
        courseId: "0kE000000000001",
        deliveryMode: "Classroom",
        discountCode: ""
      })
    });
    await Promise.resolve();
    expect(
      element.shadowRoot.querySelectorAll("table.quote tbody tr")
    ).toHaveLength(1);
  });
});
