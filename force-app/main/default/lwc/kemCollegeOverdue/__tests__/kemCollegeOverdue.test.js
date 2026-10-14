import { createElement } from "lwc";
import KemCollegeOverdue from "c/kemCollegeOverdue";
import getOverdue from "@salesforce/apex/CollegeAdmissionsController.getOverdue";
import extendPayment from "@salesforce/apex/CollegeAdmissionsController.extendPayment";
import cancelAdmission from "@salesforce/apex/CollegeAdmissionsController.cancelAdmission";

jest.mock(
  "@salesforce/apex/CollegeAdmissionsController.getOverdue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionsController.extendPayment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeAdmissionsController.cancelAdmission",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const ROW = {
  enrolmentId: "a0X000000000001",
  studentName: "Ravi Kumar",
  branchName: "CSE",
  campusName: "Yelahanka Campus",
  paymentDueBy: "2026-10-10",
  paid: 0,
  awaitingClearance: 155000,
  balanceDue: 155000
};

function mount() {
  const element = createElement("c-kem-college-overdue", {
    is: KemCollegeOverdue
  });
  document.body.appendChild(element);
  return element;
}

describe("c-kem-college-overdue", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("stays hidden for users who are not the Dean", async () => {
    getOverdue.mockResolvedValue(null);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector("section")).toBeNull();
  });

  it("extends the payment date with the entered date and reason", async () => {
    getOverdue.mockResolvedValue([ROW]);
    extendPayment.mockResolvedValue();
    const element = mount();
    await flush();
    const inputs = element.shadowRoot.querySelectorAll("lightning-input");
    inputs[0].value = "2026-10-20";
    inputs[1].value = "DD clearing";
    element.shadowRoot.querySelectorAll("lightning-button")[0].click();
    await flush();
    expect(extendPayment).toHaveBeenCalledWith({
      enrolmentId: ROW.enrolmentId,
      newDueBy: "2026-10-20",
      reason: "DD clearing"
    });
    expect(getOverdue).toHaveBeenCalledTimes(2);
  });

  it("cancels the admission with the reason", async () => {
    getOverdue.mockResolvedValue([ROW]);
    cancelAdmission.mockRejectedValue({
      body: { message: "awaiting clearance" }
    });
    const element = mount();
    await flush();
    element.shadowRoot.querySelectorAll("lightning-input")[1].value = "Left";
    element.shadowRoot.querySelectorAll("lightning-button")[1].click();
    await flush();
    expect(cancelAdmission).toHaveBeenCalledWith({
      enrolmentId: ROW.enrolmentId,
      reason: "Left"
    });
  });

  it("says when nothing is overdue", async () => {
    getOverdue.mockResolvedValue([]);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelector(".empty")).not.toBeNull();
  });
});
