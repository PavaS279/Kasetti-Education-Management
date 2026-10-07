import { createElement } from "lwc";
import KemLibraryDesk from "c/kemLibraryDesk";
import getDesk from "@salesforce/apex/LibraryController.getDesk";
import findLearners from "@salesforce/apex/LibraryController.findLearners";
import addItem from "@salesforce/apex/LibraryController.addItem";
import issue from "@salesforce/apex/LibraryController.issue";
import renew from "@salesforce/apex/LibraryController.renew";
import returnLoan from "@salesforce/apex/LibraryController.returnLoan";
import markLost from "@salesforce/apex/LibraryController.markLost";
import settleFine from "@salesforce/apex/LibraryController.settleFine";
import addCopies from "@salesforce/apex/LibrarySetupController.addCopies";
import LightningModal from "lightning/modal";

jest.mock(
  "@salesforce/apex/LibrarySetupController.addCopies",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.getDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.findLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.addItem",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.issue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.renew",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.returnLoan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.markLost",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryController.settleFine",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function desk(overrides = {}) {
  return {
    titles: 2,
    copies: 3,
    onLoan: 1,
    overdue: 1,
    finesOutstanding: 30,
    canLend: true,
    canManageItems: true,
    items: [
      {
        id: "a1",
        title: "Wings of Fire",
        code: "LIB-B-001",
        itemType: "Book",
        copies: 2,
        available: 1,
        active: true
      },
      {
        id: "a2",
        title: "Robotics Kit",
        code: "LIB-K-001",
        itemType: "Kit",
        copies: 1,
        available: 0,
        active: true
      }
    ],
    loans: [
      {
        id: "l1",
        loanNumber: "LN-000001",
        title: "Wings of Fire",
        itemCode: "LIB-B-001",
        borrower: "Lata",
        dueOn: "2026-10-01",
        daysOverdue: 5,
        canRenew: false
      },
      {
        id: "l2",
        loanNumber: "LN-000002",
        title: "Atlas",
        itemCode: "LIB-B-002",
        borrower: "Manu",
        dueOn: "2026-10-20",
        daysOverdue: 0,
        canRenew: true
      }
    ],
    finesDue: [
      {
        id: "l3",
        loanNumber: "LN-000003",
        title: "Atlas",
        borrower: "Manu",
        status: "Returned",
        fine: 30
      }
    ],
    ...overrides
  };
}

async function mount() {
  const el = createElement("c-kem-library-desk", { is: KemLibraryDesk });
  el.recordId = "a0M1";
  document.body.appendChild(el);
  await flush();
  return el;
}
const button = (root, label) =>
  [...root.querySelectorAll("lightning-button")].find((b) => b.label === label);
const tab = (el, name) =>
  el.shadowRoot.querySelector(`button[data-tab="${name}"]`);

describe("c-kem-library-desk", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows loans and runs loan actions", async () => {
    getDesk.mockResolvedValue(desk());
    renew.mockResolvedValue();
    returnLoan.mockResolvedValue(30);
    markLost.mockResolvedValue(300);
    const el = await mount();
    expect(getDesk).toHaveBeenCalledWith({ branchId: "a0M1", search: "" });
    expect(el.shadowRoot.querySelector(".count_warn").textContent).toContain(
      "1"
    );
    const rows = el.shadowRoot.querySelectorAll(".row");
    expect(rows[0].querySelector(".due_late").textContent).toBe(
      "5 day(s) overdue"
    );
    expect(button(rows[0], "Renew")).toBeUndefined();
    button(rows[1], "Renew").click();
    await flush();
    expect(renew).toHaveBeenCalledWith({ loanId: "l2" });
    button(rows[0], "Return damaged").click();
    await flush();
    expect(returnLoan).toHaveBeenCalledWith({
      loanId: "l1",
      condition: "Damaged"
    });
    button(el.shadowRoot.querySelectorAll(".row")[0], "Lost").click();
    await flush();
    expect(markLost).toHaveBeenCalledWith({ loanId: "l1" });
  });

  it("issues an item to a learner found by name", async () => {
    getDesk.mockResolvedValue(desk());
    findLearners.mockResolvedValue([{ label: "Lata Reader", value: "001L" }]);
    issue.mockResolvedValue("l9");
    const el = await mount();
    tab(el, "catalogue").click();
    await flush();
    const rows = el.shadowRoot.querySelectorAll(".row");
    expect(button(rows[1], "Issue")).toBeUndefined();
    button(rows[0], "Issue").click();
    await flush();
    const learner = el.shadowRoot.querySelector(".issue-form lightning-input");
    learner.value = "Lata";
    learner.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(findLearners).toHaveBeenCalledWith({
      branchId: "a0M1",
      search: "Lata"
    });
    const choose = el.shadowRoot.querySelector(
      ".issue-form lightning-combobox"
    );
    expect(choose.options).toHaveLength(1);
    choose.dispatchEvent(
      new CustomEvent("change", { detail: { value: "001L" } })
    );
    await flush();
    button(el.shadowRoot, "Issue item").click();
    await flush();
    expect(issue).toHaveBeenCalledWith({
      itemId: "a1",
      learnerAccountId: "001L"
    });
  });

  it("adds an item and searches the catalogue", async () => {
    getDesk.mockResolvedValue(desk());
    addItem.mockResolvedValue("a3");
    const el = await mount();
    tab(el, "catalogue").click();
    await flush();
    jest.useFakeTimers({ doNotFake: ["nextTick"] });
    const search =
      el.shadowRoot.querySelector('lightning-input[type="search"]') ||
      el.shadowRoot.querySelector(".toolbar lightning-input");
    search.value = "kalam";
    search.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(350);
    expect(getDesk).toHaveBeenLastCalledWith({
      branchId: "a0M1",
      search: "kalam"
    });
    jest.useRealTimers();
    await flush();
    button(el.shadowRoot, "Add item").click();
    await flush();
    expect(button(el.shadowRoot, "Save item").disabled).toBe(true);
    const fields = el.shadowRoot.querySelectorAll(".add-form lightning-input");
    fields[0].value = "Tablet";
    fields[0].dispatchEvent(new CustomEvent("change"));
    fields[1].value = "lib-d-001";
    fields[1].dispatchEvent(new CustomEvent("change"));
    await flush();
    button(el.shadowRoot, "Save item").click();
    await flush();
    expect(addItem).toHaveBeenCalledWith({
      item: expect.objectContaining({
        Name: "Tablet",
        Item_Code__c: "lib-d-001",
        Copies_Total__c: 1,
        Branch__c: "a0M1"
      })
    });
  });

  it("imports a catalogue and adds copies to an item", async () => {
    getDesk.mockResolvedValue(desk());
    addCopies.mockResolvedValue(1);
    const el = await mount();
    tab(el, "catalogue").click();
    await flush();
    const root = el.shadowRoot;
    LightningModal.open.mockResolvedValueOnce({
      created: 3,
      updated: 1,
      copies: 9,
      skipped: 0
    });
    button(root, "Import").click();
    await flush();
    await flush();
    expect(LightningModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        label: "Import library items",
        branchId: "a0M1"
      })
    );
    root.querySelector("lightning-button.add-copies").click();
    await flush();
    const input = root.querySelector("lightning-input.copies-input");
    input.value = "4";
    input.dispatchEvent(new CustomEvent("change"));
    await flush();
    button(root, "Add").click();
    await flush();
    await flush();
    expect(addCopies).toHaveBeenCalledWith({ itemId: "a1", copies: 4 });
  });

  it("settles fines, shows empty states and hides without access", async () => {
    getDesk.mockResolvedValue(desk());
    settleFine.mockResolvedValue();
    const el = await mount();
    tab(el, "fines").click();
    await flush();
    button(el.shadowRoot, "Waive").click();
    await flush();
    expect(settleFine).toHaveBeenCalledWith({
      loanId: "l3",
      outcome: "Waived"
    });

    getDesk.mockResolvedValue(
      desk({
        loans: [],
        items: [],
        finesDue: [],
        canLend: false,
        canManageItems: false
      })
    );
    const empty = await mount();
    expect(empty.shadowRoot.textContent).toContain("Nothing on loan.");
    tab(empty, "catalogue").click();
    await flush();
    expect(empty.shadowRoot.textContent).toContain("No items found.");
    expect(button(empty.shadowRoot, "Add item")).toBeUndefined();

    getDesk.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'LibraryController'."
      }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
