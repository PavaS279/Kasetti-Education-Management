import { createElement } from "lwc";
import KemClassSetup from "c/kemClassSetup";
import getDetails from "@salesforce/apex/ClassSetupController.getDetails";
import saveClass from "@salesforce/apex/ClassSetupController.saveClass";

jest.mock(
  "@salesforce/apex/ClassSetupController.getDetails",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ClassSetupController.saveClass",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "lightning/uiRecordApi",
  () => ({ notifyRecordUpdateAvailable: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const IND = "a0M1";

const DETAILS = {
  classId: "0P01",
  name: "Abacus Level 2 – Saturday 09:30",
  branchId: IND,
  roomId: null,
  teacherUserId: null,
  facultyId: null,
  capacity: 12,
  seatsTaken: 10,
  deliveryMode: "Classroom",
  status: "Open",
  upcomingSessions: 11,
  upcomingWithoutTeacher: 11,
  patterns: 1,
  canEdit: true,
  branches: [{ label: "KT Edutech Indiranagar", value: IND }],
  rooms: [
    { label: "Ramanujan Room (12 seats)", value: "a0R1", detail: "12" },
    { label: "Turing Lab (10 seats)", value: "a0R2", detail: "10" }
  ],
  teachers: [
    { label: "Anjali Advisor", value: "0051", detail: "Teacher at this branch" }
  ],
  otherStaff: [
    { label: "Rahul Registrar", value: "0052", detail: "Branch Manager" }
  ],
  faculty: [
    { label: "Meenakshi Raghavan", value: "0031", detail: "Faculty – Abacus" }
  ],
  statuses: [
    { label: "Open", value: "Open" },
    { label: "In Progress", value: "In Progress" }
  ]
};

const mount = async (props = {}) => {
  const el = createElement("c-kem-class-setup", { is: KemClassSetup });
  el.recordId = "0P01";
  Object.assign(el, props);
  document.body.appendChild(el);
  await settle();
  return el;
};
const change = async (el, value) => {
  el.value = value;
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await settle();
};

describe("c-kem-class-setup", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows what is missing and assigns a teacher, faculty and room", async () => {
    getDetails.mockResolvedValueOnce(DETAILS).mockResolvedValueOnce({
      ...DETAILS,
      teacherUserId: "0051",
      facultyId: "0031",
      roomId: "a0R1",
      upcomingWithoutTeacher: 0
    });
    saveClass.mockResolvedValue({ updated: 11, clashes: [] });
    const el = await mount();
    const root = el.shadowRoot;
    expect(root.textContent).toContain("No teacher login");
    expect(root.textContent).toContain("No room");
    expect(root.textContent).toContain("10 of 12 taken");
    root.querySelector("lightning-button.edit").click();
    await settle();
    const teacher = root.querySelector("lightning-combobox.teacher");
    expect(teacher.options.map((o) => o.label)).toEqual([
      "No teacher",
      "Anjali Advisor",
      "Rahul Registrar (Branch Manager)"
    ]);
    await change(teacher, "0051");
    await change(root.querySelector("lightning-combobox.faculty"), "0031");
    await change(root.querySelector("lightning-combobox.room"), "a0R2");
    // Turing Lab seats 10 but the class has 12 seats.
    expect(root.textContent).toContain("Only 10 seats for a class of 12");
    expect(root.querySelector("lightning-button.save").disabled).toBe(true);
    await change(root.querySelector("lightning-combobox.room"), "a0R1");
    expect(root.textContent).toContain("also set on the 11 upcoming sessions");
    root.querySelector("lightning-button.save").click();
    await settle();
    expect(saveClass).toHaveBeenCalledWith({
      request: {
        classId: "0P01",
        branchId: IND,
        roomId: "a0R1",
        teacherUserId: "0051",
        facultyId: "0031",
        capacity: 12,
        deliveryMode: "Classroom",
        status: "Open"
      }
    });
    expect(root.textContent).toContain("Anjali Advisor");
    expect(root.textContent).toContain("Fully set up");
  });

  it("lists clashes after saving in a modal and fires saved on Done", async () => {
    getDetails.mockResolvedValue({ ...DETAILS, teacherUserId: null });
    saveClass.mockResolvedValue({
      updated: 9,
      clashes: [
        "13/10/2026, 9:30 am: The teacher is already teaching Vedic Maths",
        "20/10/2026, 9:30 am: The teacher is already teaching Vedic Maths"
      ]
    });
    const el = await mount({ inModal: true });
    const saved = jest.fn();
    el.addEventListener("saved", saved);
    const root = el.shadowRoot;
    // Opens straight in edit mode.
    await change(root.querySelector("lightning-combobox.teacher"), "0052");
    root.querySelector("lightning-button.save").click();
    await settle();
    expect(root.textContent).toContain("9 upcoming sessions updated");
    expect(root.textContent).toContain("already teaching Vedic Maths");
    expect(saved).not.toHaveBeenCalled();
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Done")
      .click();
    expect(saved.mock.calls[0][0].detail).toEqual({ updated: 9 });
  });

  it("hides without access and explains weekly times", async () => {
    getDetails.mockResolvedValueOnce({
      ...DETAILS,
      patterns: 0,
      upcomingSessions: 0,
      canEdit: false
    });
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("Add weekly pattern");
    expect(el.shadowRoot.querySelector("lightning-button.edit")).toBeNull();
    document.body.removeChild(el);
    getDetails.mockRejectedValueOnce({
      body: {
        message:
          "You do not have access to the Apex class named 'ClassSetupController'."
      }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
