import { createElement } from "lwc";
import KemStaffModal from "c/kemStaffModal";
import getOverview from "@salesforce/apex/StaffSetupController.getOverview";
import createLogin from "@salesforce/apex/StaffSetupController.createLogin";
import assignRoles from "@salesforce/apex/StaffSetupController.assignRoles";

jest.mock(
  "@salesforce/apex/StaffSetupController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/StaffSetupController.createLogin",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/StaffSetupController.assignRoles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const IND = "a0M000000000001";
const KOR = "a0M000000000002";

const OVERVIEW = {
  freeUserLicences: 6,
  freeEducationLicences: 4,
  usernameSuffix: ".kasettitechnologiespvtltd",
  personas: [
    { label: "Teacher", value: "KEM_Teacher_Persona", detail: "Teacher" },
    { label: "Finance", value: "KEM_Finance_Persona", detail: "Finance" },
    { label: "Administrator", value: "KEM_Administrator_Persona", detail: null }
  ],
  branches: [
    { label: "Indiranagar", value: IND },
    { label: "Koramangala", value: KOR }
  ],
  roles: ["Teacher", "Finance", "Branch Manager"],
  staff: []
};

const setUp = async (overview = OVERVIEW) => {
  getOverview.mockResolvedValue(overview);
  const element = createElement("c-kem-staff-modal", { is: KemStaffModal });
  const closed = jest.fn();
  element.addEventListener("close", closed);
  document.body.appendChild(element);
  await settle();
  const root = element.shadowRoot;
  const field = (name) =>
    root.querySelector(`[data-field="${name}"]:not([data-index])`);
  const submit = () =>
    [...root.querySelectorAll("lightning-button")].find(
      (b) =>
        b.label === "Add staff member" || b.label === "Save the branch roles"
    );
  const valid = () =>
    root
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((i) => {
        i.reportValidity = () => true;
      });
  return { element, root, field, submit, valid, closed };
};
const change = (el, value) => {
  el.value = value;
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};

describe("c-kem-staff-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("creates the login, then its branch roles", async () => {
    createLogin.mockResolvedValue("005000000000NEW");
    assignRoles.mockResolvedValue(2);
    const { root, field, submit, valid, closed } = await setUp();
    expect(root.textContent).toContain(
      "6 Salesforce and 4 Education Cloud licences free"
    );
    change(field("firstName"), "Meera");
    await settle();
    change(field("lastName"), "Pillai");
    await settle();
    change(field("email"), "Meera.Pillai@ktedutech.com");
    await settle();
    expect(field("username").value).toBe(
      "meera.pillai@ktedutech.com.kasettitechnologiespvtltd"
    );
    change(field("persona"), "KEM_Finance_Persona");
    await settle();
    // The role follows what the person does.
    expect(
      root.querySelector('[data-index="0"][data-field="role"]').value
    ).toBe("Finance");
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Add another role")
      .click();
    await settle();
    change(root.querySelector('[data-index="1"][data-field="branchId"]'), KOR);
    await settle();
    valid();
    submit().click();
    await settle();
    expect(createLogin).toHaveBeenCalledWith({
      request: {
        firstName: "Meera",
        lastName: "Pillai",
        email: "Meera.Pillai@ktedutech.com",
        mobile: "",
        persona: "KEM_Finance_Persona",
        aiUser: false,
        sendEmail: true,
        username: "meera.pillai@ktedutech.com.kasettitechnologiespvtltd"
      }
    });
    expect(assignRoles).toHaveBeenCalledWith({
      userId: "005000000000NEW",
      roles: [
        { branchId: IND, role: "Finance" },
        { branchId: KOR, role: "Finance" }
      ]
    });
    expect(closed.mock.calls[0][0].detail).toEqual({
      userId: "005000000000NEW",
      roles: 2
    });
  });

  it("keeps the login when the roles fail and lets them be saved again", async () => {
    createLogin.mockResolvedValue("005000000000NEW");
    assignRoles
      .mockRejectedValueOnce({ body: { message: "Branch is inactive." } })
      .mockResolvedValueOnce(1);
    const { root, field, submit, valid, closed } = await setUp();
    change(field("lastName"), "Pillai");
    await settle();
    change(field("email"), "meera@ktedutech.com");
    await settle();
    valid();
    submit().click();
    await settle();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "The login was created, but the branch roles were not saved"
    );
    expect(submit().label).toBe("Save the branch roles");
    submit().click();
    await settle();
    expect(createLogin).toHaveBeenCalledTimes(1);
    expect(closed.mock.calls[0][0].detail).toEqual({
      userId: "005000000000NEW",
      roles: 1
    });
  });

  it("blocks adding when no licence is free", async () => {
    const { root, field, submit } = await setUp({
      ...OVERVIEW,
      freeEducationLicences: 0
    });
    change(field("lastName"), "Pillai");
    await settle();
    change(field("email"), "meera@ktedutech.com");
    await settle();
    expect(root.textContent).toContain("buy a licence first");
    expect(submit().disabled).toBe(true);
  });
});
