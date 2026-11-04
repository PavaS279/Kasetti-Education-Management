import { createElement } from "lwc";
import KemInvoice from "c/kemInvoice";
import getInvoice from "@salesforce/apex/BillingController.getInvoice";
import issueInvoice from "@salesforce/apex/BillingController.issueInvoice";
import confirmPayment from "@salesforce/apex/BillingController.confirmPayment";
import PaymentModal from "c/kemPaymentModal";
import InstalmentModal from "c/kemInstalmentModal";
import CreditModal from "c/kemCreditModal";
import removeInstalmentPlan from "@salesforce/apex/BillingController.removeInstalmentPlan";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/BillingController.getInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.issueInvoice",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.cancelInvoice",
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
  "@salesforce/apex/BillingController.removeInstalmentPlan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemCreditModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "c/kemInstalmentModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "c/kemPaymentModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function view(overrides = {}) {
  return {
    canManage: true,
    invoice: {
      Id: "a0I000000000001",
      Name: "BLR-000001",
      Status__c: "Issued",
      Total__c: 7080,
      Amount_Paid__c: 3000,
      Balance_Due__c: 4080,
      Subtotal__c: 6000,
      Tax_Total__c: 1080,
      Discount_Total__c: 0,
      Overdue__c: false,
      Bill_To__c: "003000000000009",
      Bill_To__r: { Name: "Rohit Sharma", Email: "rohit@example.com" },
      Learner__r: { Name: "Ananya Sharma" },
      Branch__r: { Name: "Bengaluru Central" },
      ...overrides
    },
    lines: [
      {
        Id: "a0L000000000001",
        Fee_Type__c: "Tuition",
        Description__c: "Term tuition",
        Unit_Amount__c: 5000,
        Discount_Amount__c: 0,
        Tax_Amount__c: 900,
        Line_Total__c: 5900
      }
    ],
    allocations: [
      {
        Id: "a0A000000000001",
        Amount__c: 3000,
        Student_Payment__c: "a0P000000000001",
        Student_Payment__r: {
          Name: "PAY-000001",
          Receipt_Number__c: "RCT-000001",
          Method__c: "UPI"
        }
      }
    ],
    pendingPayments: [
      {
        Id: "a0P000000000002",
        Name: "PAY-000002",
        Amount__c: 1000,
        Method__c: "Cheque"
      }
    ]
  };
}

async function mount() {
  const element = createElement("c-kem-invoice", { is: KemInvoice });
  element.recordId = "a0I000000000001";
  document.body.appendChild(element);
  await flush();
  return element;
}

const button = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-invoice", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows totals, payments and pending confirmations", async () => {
    getInvoice.mockResolvedValue(view());
    const element = await mount();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("BLR-000001");
    expect(text).toContain("Rohit Sharma");
    expect(text).toContain("RCT-000001");
    expect(text).toContain("Awaiting confirmation");
    expect(
      element.shadowRoot
        .querySelector(".progress")
        .getAttribute("aria-valuenow")
    ).toBe("42");
    expect(button(element, "Record payment")).toBeTruthy();
    expect(button(element, "Cancel invoice")).toBeUndefined();

    confirmPayment.mockResolvedValue({ reconciliationStatus: "Reconciled" });
    button(element, "Confirm").click();
    await flush();
    expect(confirmPayment).toHaveBeenCalledWith({
      paymentId: "a0P000000000002"
    });
  });

  it("issues a draft invoice", async () => {
    getInvoice.mockResolvedValue(
      view({ Status__c: "Draft", Amount_Paid__c: 0 })
    );
    issueInvoice.mockResolvedValue(undefined);
    const element = await mount();
    expect(button(element, "Cancel invoice")).toBeTruthy();
    button(element, "Issue invoice").click();
    await flush();
    expect(issueInvoice).toHaveBeenCalledWith({ invoiceId: "a0I000000000001" });
    expect(getInvoice).toHaveBeenCalledTimes(2);
  });

  it("opens the payment modal with the balance", async () => {
    getInvoice.mockResolvedValue(view());
    PaymentModal.open.mockResolvedValue(null);
    const element = await mount();
    button(element, "Record payment").click();
    await flush();
    expect(PaymentModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        invoiceId: "a0I000000000001",
        balance: 4080,
        payerName: "Rohit Sharma"
      })
    );
  });

  it("is read-only without billing permission", async () => {
    const readOnly = view();
    readOnly.canManage = false;
    getInvoice.mockResolvedValue(readOnly);
    const element = await mount();
    expect(button(element, "Record payment")).toBeUndefined();
    expect(button(element, "Confirm")).toBeUndefined();
  });

  it("offers an instalment plan on an open invoice", async () => {
    getInvoice.mockResolvedValue(view());
    InstalmentModal.open.mockResolvedValue(false);
    const element = await mount();
    button(element, "Pay in instalments").click();
    await flush();
    expect(InstalmentModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ invoiceId: "a0I000000000001", total: 7080 })
    );
  });

  it("shows instalments, periods and removes the plan", async () => {
    const withPlan = view({
      Billing_Period__c: "Oct 2026",
      Original_Due_Date__c: "2026-10-15"
    });
    withPlan.lines[0].Period_Start__c = "2026-10-01";
    withPlan.lines[0].Period_End__c = "2026-10-31";
    withPlan.instalments = [
      {
        Id: "a0X1",
        Sequence__c: 1,
        Due_Date__c: "2026-10-15",
        Amount__c: 3540,
        Amount_Paid__c: 3000,
        Status__c: "Partially Paid",
        Overdue__c: true
      },
      {
        Id: "a0X2",
        Sequence__c: 2,
        Due_Date__c: "2026-11-15",
        Amount__c: 3540,
        Amount_Paid__c: 0,
        Status__c: "Due",
        Overdue__c: false
      }
    ];
    getInvoice.mockResolvedValue(withPlan);
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    removeInstalmentPlan.mockResolvedValue(undefined);
    const element = await mount();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Period Oct 2026");
    expect(text).toContain("0 of 2 paid");
    expect(text).toContain("Overdue");
    expect(element.shadowRoot.querySelectorAll(".inst")).toHaveLength(2);
    expect(button(element, "Pay in instalments")).toBeUndefined();
    button(element, "Remove plan").click();
    await flush();
    await flush();
    expect(removeInstalmentPlan).toHaveBeenCalledWith({
      invoiceId: "a0I000000000001"
    });
  });

  it("issues a credit note on a paid invoice and labels credit payments", async () => {
    const paid = view({
      Status__c: "Paid",
      Amount_Paid__c: 7080,
      Balance_Due__c: 0
    });
    paid.allocations.push({
      Id: "a0A000000000002",
      Amount__c: 1000,
      Student_Payment__c: "a0P000000000009",
      Student_Payment__r: {
        Name: "PAY-000009",
        Method__c: "Credit Note",
        Reference__c: "CN-000001"
      }
    });
    getInvoice.mockResolvedValue(paid);
    CreditModal.open.mockResolvedValue(null);
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("Credit CN-000001");
    expect(button(element, "Record payment")).toBeUndefined();
    button(element, "Issue credit note").click();
    await flush();
    expect(CreditModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ invoiceId: "a0I000000000001", paid: 7080 })
    );
  });
});
