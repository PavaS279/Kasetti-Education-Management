import { createElement } from "lwc";
import KemEnrolModal from "c/kemEnrolModal";
import getEnrollableClasses from "@salesforce/apex/EnrolmentController.getEnrollableClasses";
import previewEnrolment from "@salesforce/apex/EnrolmentController.previewEnrolment";

jest.mock(
  "@salesforce/apex/EnrolmentController.searchLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.getEnrollableClasses",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.previewEnrolment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EnrolmentController.enrol",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-enrol-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("starts at the class step for a known learner and previews the price", async () => {
    getEnrollableClasses.mockResolvedValue([
      {
        Id: "0kF000000000001",
        Name: "Maths Sat AM",
        EnrollmentCapacity: 3,
        Seats_Taken__c: 1,
        LearningCourse: { Name: "Maths" }
      }
    ]);
    previewEnrolment.mockResolvedValue({
      offering: { Name: "Maths Sat AM" },
      blockers: [],
      quote: {
        lines: [
          {
            feePriceId: "a01",
            feeType: "Tuition",
            frequency: "Term",
            unitAmount: 100,
            discountAmount: 0,
            taxAmount: 18,
            total: 118
          }
        ],
        grandTotal: 118,
        warnings: []
      }
    });
    const element = createElement("c-kem-enrol-modal", { is: KemEnrolModal });
    element.learnerId = "001000000000001";
    element.learnerName = "Ananya Sharma";
    document.body.appendChild(element);
    await flush();
    const option = element.shadowRoot.querySelector("li.class-option");
    expect(option.textContent).toContain("2 of 3 seats left");
    option.click();
    await flush();
    const next = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Next");
    next.click();
    await flush();
    expect(previewEnrolment).toHaveBeenCalledWith({
      request: expect.objectContaining({
        learnerAccountId: "001000000000001",
        offeringId: "0kF000000000001"
      })
    });
    expect(
      element.shadowRoot.querySelectorAll("table.quote tbody tr")
    ).toHaveLength(1);
  });
});
