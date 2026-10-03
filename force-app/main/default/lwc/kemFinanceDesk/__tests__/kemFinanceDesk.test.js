import { createElement } from "lwc";
import KemFinanceDesk from "c/kemFinanceDesk";
import getFinanceDesk from "@salesforce/apex/BillingController.getFinanceDesk";
import resolveException from "@salesforce/apex/BillingController.resolveException";

jest.mock(
  "@salesforce/apex/BillingController.getFinanceDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.confirmPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.failPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.resolveException",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const DESK = {
  canManage: true,
  outstanding: 12000,
  overdueAmount: 4080,
  overdueCount: 1,
  collectedThisMonth: 9000,
  pending: [],
  exceptions: [
    {
      Id: "a0P000000000003",
      Receipt_Number__c: "RCT-000003",
      Unallocated_Amount__c: 920,
      Reconciliation_Note__c: "920.00 could not be allocated",
      Payer__r: { Name: "Rohit Sharma" }
    }
  ],
  overdue: [
    {
      Id: "a0I000000000001",
      Name: "BLR-000001",
      Due_Date__c: "2026-01-01",
      Balance_Due__c: 4080,
      Bill_To__r: { Name: "Rohit Sharma" },
      Learner__r: { Name: "Ananya Sharma" }
    }
  ],
  recent: []
};

describe("c-kem-finance-desk", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows KPIs and work queues and retries an exception", async () => {
    getFinanceDesk.mockResolvedValue(DESK);
    resolveException.mockResolvedValue({ reconciliationStatus: "Reconciled" });
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();

    const values = [...element.shadowRoot.querySelectorAll(".kpi-value")].map(
      (n) => n.value
    );
    expect(values).toEqual([12000, 4080, 9000]);
    expect(element.shadowRoot.textContent).toContain(
      "No payments are waiting for confirmation."
    );

    element.shadowRoot.querySelector('button[data-value="exceptions"]').click();
    await flush();
    expect(element.shadowRoot.textContent).toContain("RCT-000003");
    const retry = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Retry allocation");
    retry.click();
    await flush();
    expect(resolveException).toHaveBeenCalledWith({
      paymentId: "a0P000000000003",
      note: null
    });

    element.shadowRoot.querySelector('button[data-value="overdue"]').click();
    await flush();
    expect(element.shadowRoot.textContent).toContain("days overdue");
  });

  it("shows load errors", async () => {
    getFinanceDesk.mockRejectedValue({ body: { message: "No access" } });
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("No access");
  });
});
