import { createElement } from "lwc";
import KemBranchWizardModal from "c/kemBranchWizardModal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import getSuggestedHolidays from "@salesforce/apex/SiteSetupController.getSuggestedHolidays";
import createBranch from "@salesforce/apex/SiteSetupController.createBranch";

jest.mock(
  "@salesforce/apex/SiteSetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SiteSetupController.getSuggestedHolidays",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SiteSetupController.createBranch",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const MANAGER = "005000000000001";

const validAll = (root) => {
  root
    .querySelectorAll(
      "lightning-input, lightning-combobox, lightning-checkbox-group"
    )
    .forEach((i) => {
      i.reportValidity = () => true;
    });
  root
    .querySelectorAll("c-kem-room-lines, c-kem-holiday-lines")
    .forEach((c) => {
      validAll(c.shadowRoot);
    });
};
const change = (el, value) => {
  el.value = value;
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};

describe("c-kem-branch-wizard-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("opens a branch with policies, rooms and the year's holidays", async () => {
    getChoices.mockResolvedValue({
      year: 2026,
      managers: [{ label: "Rahul Registrar", value: MANAGER }],
      suggestedHolidays: [
        {
          name: "Kannada Rajyotsava",
          startDate: "2099-11-01",
          endDate: "2099-11-01",
          closureType: "Public Holiday",
          checkDate: false
        },
        {
          name: "Republic Day",
          startDate: "2000-01-26",
          endDate: "2000-01-26",
          closureType: "Public Holiday",
          checkDate: false
        }
      ]
    });
    createBranch.mockResolvedValue({
      branchId: "a0M0000000000NEW",
      rooms: 1,
      holidays: 1
    });
    const element = createElement("c-kem-branch-wizard-modal", {
      is: KemBranchWizardModal
    });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const field = (name) => root.querySelector(`[data-field="${name}"]`);
    const button = (label) =>
      [...root.querySelectorAll("lightning-button")].find(
        (b) => b.label === label
      );
    const next = async () => {
      validAll(root);
      button("Next").click();
      await settle();
    };

    change(field("name"), "KT Edutech Jayanagar");
    await settle();
    change(field("code"), "jpn-01");
    await settle();
    // The invoice prefix follows the code until it is typed.
    expect(field("invoicePrefix").value).toBe("JPN");
    change(field("managerUserId"), MANAGER);
    await settle();
    await next();

    expect(field("taxRate").value).toBe(18);
    change(field("postalCode"), "560041");
    await settle();
    await next();

    // Rooms: the starting line has 12 seats; name it.
    const rooms = root.querySelector("c-kem-room-lines").shadowRoot;
    change(rooms.querySelector('[data-field="name"]'), "Aryabhata Room");
    await settle();
    await next();

    // Holidays: the past one is unticked.
    expect(
      root.querySelector("c-kem-holiday-lines").shadowRoot.textContent
    ).toContain("1 chosen");
    await next();

    const summary = root.querySelector("dl.summary").textContent;
    expect(summary).toContain("KT Edutech Jayanagar (jpn-01)");
    expect(summary).toContain("Rahul Registrar");
    expect(summary).toContain("1 rooms, 12 seats");
    expect(summary).toContain("1 holidays and breaks");
    button("Open the branch").click();
    await settle();
    const request = createBranch.mock.calls[0][0].request;
    expect(request).toMatchObject({
      name: "KT Edutech Jayanagar",
      code: "jpn-01",
      invoicePrefix: "JPN",
      managerUserId: MANAGER,
      postalCode: "560041",
      taxRate: 18,
      deliveryModes: ["Classroom"],
      rooms: [{ name: "Aryabhata Room", roomType: "Classroom", capacity: 12 }],
      holidays: [{ name: "Kannada Rajyotsava", startDate: "2099-11-01" }]
    });
    expect(closed.mock.calls[0][0].detail).toEqual({
      branchId: "a0M0000000000NEW",
      rooms: 1,
      holidays: 1
    });
  });

  it("keeps the person on the summary when the server refuses", async () => {
    getChoices.mockResolvedValue({
      year: 2026,
      managers: [],
      suggestedHolidays: []
    });
    getSuggestedHolidays.mockResolvedValue([
      {
        name: "Ugadi",
        startDate: "2099-04-07",
        endDate: "2099-04-07",
        closureType: "Public Holiday",
        checkDate: true
      }
    ]);
    createBranch.mockRejectedValue({
      body: {
        message: "Branch code JPN-01 is already used by KT Edutech Jayanagar."
      }
    });
    const element = createElement("c-kem-branch-wizard-modal", {
      is: KemBranchWizardModal
    });
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const button = (label) =>
      [...root.querySelectorAll("lightning-button")].find(
        (b) => b.label === label
      );
    for (let i = 0; i < 3; i++) {
      validAll(root);
      button("Next").click();
      // eslint-disable-next-line no-await-in-loop
      await settle();
    }
    button("Suggest the year's holidays").click();
    await settle();
    expect(getSuggestedHolidays).toHaveBeenCalledWith({ year: 2026 });
    expect(
      root.querySelector("c-kem-holiday-lines").shadowRoot.textContent
    ).toContain("Check date");
    validAll(root);
    button("Next").click();
    await settle();
    expect(root.textContent).toContain("No manager yet");
    button("Open the branch").click();
    await settle();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "already used"
    );
    expect(root.querySelector("dl.summary")).not.toBeNull();
  });
});
