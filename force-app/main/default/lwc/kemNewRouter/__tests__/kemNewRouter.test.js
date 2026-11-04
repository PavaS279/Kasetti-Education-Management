import { createElement } from "lwc";
import KemNewRouter, { parentFrom, fieldValuesFrom } from "c/kemNewRouter";
import getContext from "@salesforce/apex/NewRouterController.getContext";
import LightningModal from "lightning/modal";
import { getNavigateCalledWith } from "lightning/navigation";

jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol("Navigate");
    let last;
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](pageRef) {
          last = pageRef;
        }
      };
    NavigationMixin.Navigate = Navigate;
    return {
      __esModule: true,
      NavigationMixin,
      getNavigateCalledWith: () => last
    };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/NewRouterController.getContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const BRANCH = "a0M000000000001";
const ref = (objectApiName, state = {}) => ({
  type: "standard__objectPage",
  attributes: { objectApiName, actionName: "new" },
  state
});
const fromBranch = `1.${btoa(
  JSON.stringify({
    type: "standard__recordPage",
    attributes: {
      recordId: BRANCH,
      objectApiName: "Branch__c",
      actionName: "view"
    }
  })
)}`;

async function mount(pageReference) {
  const el = createElement("c-kem-new-router", { is: KemNewRouter });
  el.pageReference = pageReference;
  document.body.appendChild(el);
  await settle();
  return el;
}

describe("c-kem-new-router", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("reads the parent record and default values", () => {
    expect(parentFrom(fromBranch)).toEqual({
      recordId: BRANCH,
      objectApiName: "Branch__c"
    });
    expect(parentFrom("not-base64")).toBeNull();
    expect(fieldValuesFrom("Branch__c=a0M1,Name=Turing%20Lab")).toEqual({
      Branch__c: "a0M1",
      Name: "Turing Lab"
    });
  });

  it("sends staff straight to the guided screen and opens the new record", async () => {
    getContext.mockResolvedValue({
      objectLabel: "Class",
      wizard: "class",
      isAdministrator: false
    });
    LightningModal.open.mockResolvedValueOnce({
      classId: "0P0NEW",
      sessions: 12
    });
    await mount(ref("CourseOffering", { inContextOfRef: fromBranch }));
    expect(getContext).toHaveBeenCalledWith({
      objectApiName: "CourseOffering",
      recordTypeId: null
    });
    expect(LightningModal.open.mock.calls[0][0]).toMatchObject({
      label: "New class",
      branchId: BRANCH
    });
    expect(getNavigateCalledWith()).toEqual({
      type: "standard__recordPage",
      attributes: { recordId: "0P0NEW", actionName: "view" }
    });
  });

  it("goes back to the parent record when a room screen is closed", async () => {
    getContext.mockResolvedValue({
      objectLabel: "Room",
      wizard: "room",
      isAdministrator: false
    });
    LightningModal.open.mockResolvedValueOnce(2);
    await mount(ref("Room__c", { inContextOfRef: fromBranch }));
    expect(LightningModal.open.mock.calls[0][0].branchId).toBe(BRANCH);
    expect(getNavigateCalledWith().attributes.recordId).toBe(BRANCH);
  });

  it("lets administrators choose, and keeps the standard form without a guided screen", async () => {
    getContext.mockResolvedValue({
      objectLabel: "Branch",
      wizard: "branch",
      isAdministrator: true
    });
    const el = await mount(ref("Branch__c"));
    expect(el.shadowRoot.textContent).toContain("New Branch");
    expect(LightningModal.open).not.toHaveBeenCalled();
    el.shadowRoot.querySelector("lightning-button.standard").click();
    expect(getNavigateCalledWith()).toEqual({
      type: "standard__objectPage",
      attributes: { objectApiName: "Branch__c", actionName: "new" },
      state: { nooverride: "1" }
    });

    LightningModal.open.mockResolvedValueOnce(null);
    el.shadowRoot.querySelector("lightning-button.guided").click();
    await settle();
    expect(LightningModal.open.mock.calls[0][0].label).toBe("New branch");
    expect(getNavigateCalledWith().attributes.actionName).toBe("list");

    document.body.removeChild(el);
    getContext.mockResolvedValue({
      objectLabel: "Account",
      wizard: null,
      isAdministrator: true
    });
    await mount(ref("Account", { recordTypeId: "012BUSINESS" }));
    expect(getNavigateCalledWith().state).toEqual({
      nooverride: "1",
      recordTypeId: "012BUSINESS"
    });
  });

  it("chains a new course into a new class", async () => {
    getContext.mockResolvedValue({
      objectLabel: "Course",
      wizard: "course",
      isAdministrator: false
    });
    LightningModal.open
      .mockResolvedValueOnce({ courseId: "0ZVNEW", addClass: true })
      .mockResolvedValueOnce(null);
    await mount(ref("LearningCourse"));
    expect(LightningModal.open.mock.calls[1][0]).toMatchObject({
      label: "New class",
      courseId: "0ZVNEW"
    });
    expect(getNavigateCalledWith().attributes.recordId).toBe("0ZVNEW");
  });

  it("opens New family for person accounts and shows errors", async () => {
    getContext.mockResolvedValueOnce({
      objectLabel: "Account",
      wizard: "family",
      isAdministrator: false
    });
    LightningModal.open.mockResolvedValueOnce({ learnerIds: ["001L1"] });
    await mount(ref("Account", { recordTypeId: "012PERSON" }));
    expect(LightningModal.open.mock.calls[0][0].label).toBe("New family");
    expect(getNavigateCalledWith().attributes.recordId).toBe("001L1");

    getContext.mockRejectedValueOnce({
      body: { message: "Unknown object Nope__c." }
    });
    const el = await mount(ref("Nope__c"));
    expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
      "Unknown object"
    );
  });
});
