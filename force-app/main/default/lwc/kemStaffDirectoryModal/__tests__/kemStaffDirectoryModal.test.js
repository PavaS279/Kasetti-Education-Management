import { createElement } from "lwc";
import KemStaffDirectoryModal from "c/kemStaffDirectoryModal";
import LightningConfirm from "lightning/confirm";
import getOverview from "@salesforce/apex/StaffSetupController.getOverview";
import assignRoles from "@salesforce/apex/StaffSetupController.assignRoles";
import endRole from "@salesforce/apex/StaffSetupController.endRole";

jest.mock(
  "@salesforce/apex/StaffSetupController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/StaffSetupController.assignRoles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/StaffSetupController.endRole",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);

const OVERVIEW = {
  branches: [
    { label: "Indiranagar", value: "a0M1" },
    { label: "HSR Layout", value: "a0M2" }
  ],
  roles: ["Teacher", "Finance"],
  personas: [],
  staff: [
    {
      userId: "0051",
      name: "Anjali Advisor",
      email: "anjali@example.com",
      persona: "Academic coordinator",
      active: true,
      roles: [
        { id: "a0S1", branchId: "a0M2", branch: "HSR Layout", role: "Teacher" }
      ]
    },
    {
      userId: "0052",
      name: "Rahul Registrar",
      email: "rahul@example.com",
      persona: "Branch manager",
      active: true,
      roles: []
    }
  ]
};

describe("c-kem-staff-directory-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists staff, finds them, adds and ends roles", async () => {
    getOverview.mockResolvedValue(OVERVIEW);
    assignRoles.mockResolvedValue(1);
    endRole.mockResolvedValue();
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    const element = createElement("c-kem-staff-directory-modal", {
      is: KemStaffDirectoryModal
    });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    expect(root.querySelectorAll("li.person")).toHaveLength(2);
    expect(root.textContent).toContain("No branch roles");

    const search = root.querySelector("lightning-input.search");
    search.value = "hsr";
    search.dispatchEvent(new CustomEvent("change"));
    await settle();
    expect(root.querySelectorAll("li.person")).toHaveLength(1);
    search.value = "";
    search.dispatchEvent(new CustomEvent("change"));
    await settle();

    const person = root.querySelectorAll("li.person")[1];
    [...person.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Add role")
      .click();
    await settle();
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Add")
      .click();
    await settle();
    expect(assignRoles).toHaveBeenCalledWith({
      userId: "0052",
      roles: [{ branchId: "a0M1", role: "Teacher" }]
    });

    root.querySelector("button.chip-end").click();
    await settle();
    expect(LightningConfirm.open).toHaveBeenCalled();
    expect(endRole).toHaveBeenCalledWith({ branchStaffId: "a0S1" });
    expect(getOverview).toHaveBeenCalledTimes(3);

    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Done")
      .click();
    expect(closed.mock.calls[0][0].detail).toBe(true);
  });
});
