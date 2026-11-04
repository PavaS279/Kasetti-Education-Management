import { createElement } from "lwc";
import KemCreditNote from "c/kemCreditNote";
import getCreditNote from "@salesforce/apex/CreditController.getCreditNote";
import applyCredit from "@salesforce/apex/CreditController.applyCredit";
import approveRefund from "@salesforce/apex/CreditController.approveRefund";
import RefundModal from "c/kemRefundModal";
import LightningConfirm from "lightning/confirm";

jest.mock(
  "@salesforce/apex/CreditController.getCreditNote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CreditController.applyCredit",
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
  "@salesforce/apex/CreditController.voidCreditNote",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemRefundModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);
jest.mock(
  "c/kemReasonModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function view(overrides = {}) {
  return {
    canManage: true,
    canApprove: true,
    currentUserId: "005000000000001",
    available: 1000,
    reserved: 2000,
    autoApproveLimit: 1000,
    creditNote: {
      Id: "a0C000000000001",
      Name: "CN-000001",
      Status__c: "Partially Used",
      Origin__c: "Withdrawal",
      Reason__c: "Left after one month",
      Issue_Date__c: "2026-10-05",
      Amount__c: 3500,
      Amount_Applied__c: 0,
      Amount_Refunded__c: 500,
      Balance__c: 3000,
      Bill_To__c: "003000000000001",
      Bill_To__r: { Name: "Rohit Sharma", Email: "rohit@example.com" },
      Learner__r: { Name: "Ananya Sharma" },
      Branch__r: { Name: "Bengaluru Central" },
      Source_Invoice__c: "a0I000000000001",
      Source_Invoice__r: { Name: "BLR-000001" },
      ...overrides
    },
    applications: [],
    openInvoices: [
      {
        Id: "a0I000000000002",
        Name: "BLR-000002",
        Due_Date__c: "2026-10-20",
        Balance_Due__c: 7080,
        Enrolment__r: { CourseOffering: { Name: "Maths" } }
      }
    ],
    refunds: [
      {
        Id: "a0R000000000001",
        Name: "RFD-000001",
        Status__c: "Requested",
        Amount__c: 2000,
        Method__c: "Bank Transfer",
        Requested_By__c: "005000000000002",
        Requested_By__r: { Name: "Finance User" },
        CreatedDate: "2026-10-05T10:00:00.000Z"
      },
      {
        Id: "a0R000000000002",
        Name: "RFD-000002",
        Status__c: "Paid",
        Amount__c: 500,
        Method__c: "UPI",
        Auto_Approved__c: true,
        Paid_On__c: "2026-10-05",
        Reference__c: "UPI-1",
        Requested_By__c: "005000000000001",
        Requested_By__r: { Name: "Me" },
        CreatedDate: "2026-10-05T09:00:00.000Z"
      }
    ]
  };
}

async function mount() {
  const element = createElement("c-kem-credit-note", { is: KemCreditNote });
  element.recordId = "a0C000000000001";
  document.body.appendChild(element);
  await flush();
  return element;
}

const button = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-credit-note", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows balance, reservations, refunds and open invoices", async () => {
    getCreditNote.mockResolvedValue(view());
    const element = await mount();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("CN-000001");
    expect(text).toContain("reserved by refunds in progress");
    expect(text).toContain("auto-approved");
    expect(text).toContain("BLR-000002");
    expect(
      element.shadowRoot
        .querySelector(".progress")
        .getAttribute("aria-valuenow")
    ).toBe("14");
    expect(button(element, "Void credit note")).toBeUndefined();
  });

  it("applies credit after confirmation and approves another user's refund", async () => {
    getCreditNote.mockResolvedValue(view());
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    applyCredit.mockResolvedValue(1000);
    approveRefund.mockResolvedValue(undefined);
    const element = await mount();
    button(element, "Apply").click();
    await flush();
    await flush();
    expect(applyCredit).toHaveBeenCalledWith({
      creditNoteId: "a0C000000000001",
      invoiceId: "a0I000000000002",
      amount: null
    });
    button(element, "Approve").click();
    await flush();
    expect(approveRefund).toHaveBeenCalledWith({ refundId: "a0R000000000001" });
  });

  it("opens the refund dialog with the available amount", async () => {
    getCreditNote.mockResolvedValue(view());
    RefundModal.open.mockResolvedValue(null);
    const element = await mount();
    button(element, "Request refund").click();
    await flush();
    expect(RefundModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ available: 1000, autoApproveLimit: 1000 })
    );
  });

  it("hides approval for the requester and offers void on unused credit", async () => {
    const unused = view({
      Status__c: "Open",
      Amount_Refunded__c: 0,
      Balance__c: 3500
    });
    unused.reserved = 0;
    unused.refunds = [];
    unused.currentUserId = "005000000000002";
    getCreditNote.mockResolvedValue(unused);
    const element = await mount();
    expect(button(element, "Approve")).toBeUndefined();
    expect(button(element, "Void credit note")).toBeTruthy();
    expect(element.shadowRoot.textContent).toContain("No refunds requested.");
  });
});
