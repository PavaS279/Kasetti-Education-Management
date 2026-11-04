import { createElement } from "lwc";
import KemTransferModal from "c/kemTransferModal";
import getEnrollableClasses from "@salesforce/apex/EnrolmentController.getEnrollableClasses";
import previewTransfer from "@salesforce/apex/TransferController.previewTransfer";
import transfer from "@salesforce/apex/TransferController.transfer";

jest.mock(
  "@salesforce/apex/EnrolmentController.getEnrollableClasses",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransferController.previewTransfer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TransferController.transfer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-transfer-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("previews the price difference and transfers", async () => {
    getEnrollableClasses.mockResolvedValue([
      { Id: "0P0CURRENT", Name: "Current" },
      {
        Id: "0P0TARGET",
        Name: "Maths Sunday",
        EnrollmentCapacity: 10,
        Seats_Available__c: 4,
        LearningCourse: { Name: "Maths" }
      }
    ]);
    previewTransfer.mockResolvedValue({
      currentTotal: 1180,
      newTotal: 1770,
      difference: 590,
      alreadyInvoiced: true,
      billingOutcome:
        "Already invoiced: only the difference is billed on the new enrolment.",
      blockers: []
    });
    transfer.mockResolvedValue("0kXNEW");
    const element = createElement("c-kem-transfer-modal", {
      is: KemTransferModal
    });
    element.enrolmentId = "0kXOLD";
    element.learnerName = "Tara";
    element.currentOfferingId = "0P0CURRENT";
    document.body.appendChild(element);
    await flush();

    const options = element.shadowRoot.querySelectorAll("button.option");
    expect(options).toHaveLength(1);
    options[0].click();
    await flush();
    expect(previewTransfer).toHaveBeenCalledWith({
      request: expect.objectContaining({
        enrolmentId: "0kXOLD",
        targetOfferingId: "0P0TARGET"
      })
    });
    expect(element.shadowRoot.textContent).toContain("only the difference");
    expect(element.shadowRoot.querySelector(".diff_up")).not.toBeNull();

    const button = () =>
      [...element.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Transfer"
      );
    expect(button().disabled).toBe(true);
    const reason = [
      ...element.shadowRoot.querySelectorAll("lightning-input")
    ].find((i) => i.label === "Reason");
    reason.value = "Prefers Sunday";
    reason.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(button().disabled).toBe(false);
    button().click();
    await flush();
    expect(transfer).toHaveBeenCalledWith({
      request: expect.objectContaining({ reason: "Prefers Sunday" })
    });
  });
});
