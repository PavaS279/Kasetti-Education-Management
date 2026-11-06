import { createElement } from "lwc";
import KemFinanceDesk from "c/kemFinanceDesk";
import getFinanceDesk from "@salesforce/apex/BillingController.getFinanceDesk";
import resolveException from "@salesforce/apex/BillingController.resolveException";
import getRefundQueue from "@salesforce/apex/CreditController.getRefundQueue";
import holdOverpayment from "@salesforce/apex/CreditController.holdOverpayment";
import approveRefund from "@salesforce/apex/CreditController.approveRefund";
import markRefundPaid from "@salesforce/apex/CreditController.markRefundPaid";
import ReasonModal from "c/kemReasonModal";
import DiscountManager from "c/kemDiscountManagerModal";

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

jest.mock(
  "@salesforce/apex/CreditController.getRefundQueue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CreditController.holdOverpayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CreditController.approveRefund",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CreditController.rejectRefund",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CreditController.markRefundPaid",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemReasonModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const DESK = {
  canManage: true,
  canCollect: true,
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

const QUEUE = {
  canManage: true,
  canApprove: true,
  currentUserId: "005000000000001",
  openCreditTotal: 2500,
  openCredits: [],
  awaitingApproval: [
    {
      Id: "a0R000000000001",
      Name: "RFD-000001",
      Status__c: "Requested",
      Amount__c: 2000,
      Method__c: "Bank Transfer",
      Reason__c: "Withdrawal",
      CreatedDate: "2026-10-05T10:00:00.000Z",
      Requested_By__c: "005000000000002",
      Requested_By__r: { Name: "Finance User" },
      Payee__r: { Name: "Rohit Sharma" },
      Credit_Note__c: "a0C000000000001",
      Credit_Note__r: { Name: "CN-000001" }
    },
    {
      Id: "a0R000000000002",
      Name: "RFD-000002",
      Status__c: "Requested",
      Amount__c: 1500,
      Method__c: "UPI",
      Reason__c: "Overpaid",
      CreatedDate: "2026-10-05T11:00:00.000Z",
      Requested_By__c: "005000000000001",
      Requested_By__r: { Name: "Me" },
      Payee__r: { Name: "Priya Nair" },
      Credit_Note__c: "a0C000000000002",
      Credit_Note__r: { Name: "CN-000002" }
    }
  ],
  awaitingPayout: [
    {
      Id: "a0R000000000003",
      Name: "RFD-000003",
      Status__c: "Approved",
      Amount__c: 500,
      Method__c: "UPI",
      Reason__c: "Withdrawal",
      CreatedDate: "2026-10-04T10:00:00.000Z",
      Requested_By__c: "005000000000002",
      Requested_By__r: { Name: "Finance User" },
      Payee__r: { Name: "Rohit Sharma" },
      Credit_Note__c: "a0C000000000001",
      Credit_Note__r: { Name: "CN-000001" }
    }
  ]
};

describe("c-kem-finance-desk", () => {
  beforeEach(() => {
    getRefundQueue.mockResolvedValue(QUEUE);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("opens on the college invoices, linking each to its invoice", async () => {
    getFinanceDesk.mockResolvedValue({
      ...DESK,
      collegeInvoices: [
        {
          Id: "a0I000000000389",
          Name: "YLK-000389",
          Status__c: "Issued",
          Total__c: 155000,
          Balance_Due__c: 155000,
          Due_Date__c: "2026-11-11",
          Learner__r: { Name: "Spoorti B" },
          Branch__r: { Name: "Yelahanka Campus" },
          Programme_Enrolment__r: { Status__c: "Provisional" }
        },
        {
          Id: "a0I000000000390",
          Name: "YLK-000390",
          Status__c: "Paid",
          Total__c: 155000,
          Balance_Due__c: 0,
          Learner__r: { Name: "Ravi Kumar" },
          Branch__r: { Name: "Yelahanka Campus" },
          Programme_Enrolment__r: {
            Status__c: "Enrolled",
            Roll_Number__c: "KT26YBCS001"
          }
        }
      ]
    });
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("College invoices");
    expect(text).toContain("YLK-000389");
    expect(text).toContain("Spoorti B · Yelahanka Campus · due");
    expect(text).toContain("enrolment number KT26YBCS001");
    expect(
      element.shadowRoot.querySelector('a[data-id="a0I000000000389"]')
    ).not.toBeNull();
  });

  it("gives the admission counsellor a college-only desk", async () => {
    getFinanceDesk.mockResolvedValue({
      ...DESK,
      canManage: false,
      canCollect: true,
      collegeOnly: true,
      exceptions: [],
      pending: [
        {
          Id: "a0P000000000009",
          Name: "PAY-000009",
          Amount__c: 155000,
          Method__c: "Demand Draft",
          Status__c: "Pending",
          Student_Invoice__c: "a0I000000000389",
          Student_Invoice__r: { Name: "YLK-000389" },
          Payer__r: { Name: "Spoorti B" }
        }
      ],
      collegeInvoices: []
    });
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();
    await flush();
    expect(getRefundQueue).not.toHaveBeenCalled();
    const tabs = [
      ...element.shadowRoot.querySelectorAll("button[data-value]")
    ].map((b) => b.dataset.value);
    expect(tabs).toEqual(["college", "pending", "overdue"]);
    expect(
      element.shadowRoot.querySelector("lightning-button.discounts")
    ).toBeNull();
    element.shadowRoot.querySelector('button[data-value="pending"]').click();
    await flush();
    const labels = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].map((b) => b.label);
    expect(labels).toContain("Confirm");
    expect(
      element.shadowRoot.querySelector('a[data-id="a0I000000000389"]')
    ).not.toBeNull();
  });

  it("has no recent receipts tab", async () => {
    getFinanceDesk.mockResolvedValue(DESK);
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();
    await flush();
    expect(element.shadowRoot.textContent).toContain("Overdue invoices");
    expect(element.shadowRoot.textContent).not.toContain("Recent receipts");
  });

  it("opens the discount codes", async () => {
    getFinanceDesk.mockResolvedValue(DESK);
    const element = createElement("c-kem-finance-desk", { is: KemFinanceDesk });
    document.body.appendChild(element);
    await flush();
    DiscountManager.open.mockResolvedValueOnce(false);
    element.shadowRoot.querySelector("lightning-button.discounts").click();
    await flush();
    expect(DiscountManager.open).toHaveBeenCalledWith(
      expect.objectContaining({ label: "Discounts", size: "large" })
    );
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
    expect(values).toEqual([12000, 4080, 9000, 2500]);
    element.shadowRoot.querySelector('button[data-value="pending"]').click();
    await flush();
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

  it("shows open credit and holds an overpayment as credit", async () => {
    getFinanceDesk.mockResolvedValue(DESK);
    holdOverpayment.mockResolvedValue("a0C000000000009");
    const element = createElement("c-kem-finance-desk", {
      is: KemFinanceDesk
    });
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.querySelectorAll(".kpi")).toHaveLength(4);
    expect(element.shadowRoot.textContent).toContain("Open credit");
    element.shadowRoot.querySelector('button[data-value="exceptions"]').click();
    await flush();
    [...element.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Hold as credit")
      .click();
    await flush();
    expect(holdOverpayment).toHaveBeenCalledWith({
      paymentId: "a0P000000000003"
    });
  });

  it("lists refunds and lets an approver decide others' requests", async () => {
    getFinanceDesk.mockResolvedValue(DESK);
    approveRefund.mockResolvedValue(undefined);
    markRefundPaid.mockResolvedValue(undefined);
    ReasonModal.open.mockResolvedValue("NEFT-123");
    const element = createElement("c-kem-finance-desk", {
      is: KemFinanceDesk
    });
    document.body.appendChild(element);
    await flush();
    element.shadowRoot.querySelector('button[data-value="refunds"]').click();
    await flush();
    const rows = element.shadowRoot.querySelectorAll(".row");
    expect(rows).toHaveLength(3);
    const buttons = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ];
    // Own request: no approve button for it, only for the other requester's.
    expect(buttons.filter((b) => b.label === "Approve")).toHaveLength(1);
    buttons.find((b) => b.label === "Approve").click();
    await flush();
    expect(approveRefund).toHaveBeenCalledWith({
      refundId: "a0R000000000001"
    });
    buttons.find((b) => b.label === "Mark paid").click();
    await flush();
    await flush();
    expect(markRefundPaid).toHaveBeenCalledWith({
      refundId: "a0R000000000003",
      reference: "NEFT-123",
      paidOn: null
    });
  });
});
