import { createElement } from "lwc";
import KemClassWizardModal from "c/kemClassWizardModal";
import getChoices from "@salesforce/apex/CatalogSetupController.getChoices";
import getBranchChoices from "@salesforce/apex/CatalogSetupController.getBranchChoices";
import previewClass from "@salesforce/apex/CatalogSetupController.previewClass";
import createClass from "@salesforce/apex/CatalogSetupController.createClass";
import createFaculty from "@salesforce/apex/CatalogSetupController.createFaculty";

jest.mock(
  "@salesforce/apex/CatalogSetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CatalogSetupController.getBranchChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CatalogSetupController.previewClass",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CatalogSetupController.createClass",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CatalogSetupController.createFaculty",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush).then(flush);

const COURSE = "0ZV000000000001";
const BRANCH = "a0M000000000001";
const ROOM = "a0R000000000001";
const TEACHER = "005000000000001";

const CHOICES = {
  courses: [{ label: "Python for Kids", value: COURSE }],
  branches: [{ label: "KT Edutech Indiranagar", value: BRANCH }],
  faculty: [
    {
      label: "Karthik Iyengar",
      value: "003000000000001",
      detail: "Faculty – Robotics"
    }
  ],
  canCreateFaculty: true
};
const BRANCH_CHOICES = {
  rooms: [{ label: "Turing Lab (10 seats)", value: ROOM, detail: "10" }],
  teachers: [{ label: "Kasetti Tech", value: TEACHER }]
};
const PREVIEW = {
  sessions: 12,
  skippedHolidays: 1,
  clashes: [
    "Sat 14 Nov 12:00: Turing Lab is booked for Python for Kids – Saturday 12:00"
  ],
  firstSessions: ["2026-10-10T06:30:00.000Z", "2026-10-17T06:30:00.000Z"],
  lastSession: "2026-12-19T06:30:00.000Z",
  warnings: ["Python for Kids has no tuition price: enrolments would be free."]
};

const change = (el, value) => {
  el.value = value;
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};

const setUp = async (props = {}) => {
  getChoices.mockResolvedValue(CHOICES);
  getBranchChoices.mockResolvedValue(BRANCH_CHOICES);
  const element = createElement("c-kem-class-wizard-modal", {
    is: KemClassWizardModal
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  await settle();
  const $ = (sel) => element.shadowRoot.querySelector(sel);
  const all = (sel) => [...element.shadowRoot.querySelectorAll(sel)];
  const button = (label) =>
    all("lightning-button").find((b) => b.label === label);
  const field = (name) => $(`[data-field="${name}"]`);
  return { element, $, all, button, field };
};

describe("c-kem-class-wizard-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("walks through the steps, previews the sessions and creates the class", async () => {
    previewClass.mockResolvedValue(PREVIEW);
    createClass.mockResolvedValue({ ...PREVIEW, classId: "0P0000000000001" });
    const { element, $, all, button, field } = await setUp();
    const closed = jest.fn();
    element.addEventListener("close", closed);

    // Step 1 needs a course and branch.
    button("Next").click();
    await settle();
    expect($('[role="alert"]').textContent).toContain("Choose the course");
    change(field("courseId"), COURSE);
    change(field("branchId"), BRANCH);
    change(field("capacity"), "10");
    await settle();
    button("Next").click();
    await settle();
    expect(getBranchChoices).toHaveBeenCalledWith({ branchId: BRANCH });

    // Step 2: a room too small for the class is caught before the server.
    change(field("roomId"), ROOM);
    change(field("teacherUserId"), TEACHER);
    await settle();
    expect(element.shadowRoot.textContent).not.toContain("Only 10 seats");
    button("Next").click();
    await settle();

    // Step 3: days are required.
    button("Next").click();
    await settle();
    expect($('[role="alert"]').textContent).toContain("day(s)");
    const sat = all("button.chip").find((b) => b.dataset.day === "Sat");
    sat.click();
    await settle();
    expect(sat.getAttribute("aria-pressed")).toBe("true");
    const time = $("lightning-input.time");
    change(time, "12:00:00.000");
    change($("lightning-combobox.length"), "90");
    await settle();
    button("Next").click();
    await settle();

    // Step 4: the preview, then create anyway despite the clash.
    const request = previewClass.mock.calls[0][0].request;
    expect(request).toMatchObject({
      courseId: COURSE,
      branchId: BRANCH,
      roomId: ROOM,
      teacherUserId: TEACHER,
      capacity: 10,
      facultyId: null,
      openForEnrolment: true,
      patterns: [{ days: ["Sat"], startTime: "12:00", minutes: 90 }]
    });
    const text = element.shadowRoot.textContent;
    expect(text).toContain("clashing sessions, not created");
    expect(text).toContain("Turing Lab is booked");
    expect(text).toContain("no tuition price");
    expect(all("ul.sessions li")).toHaveLength(2);
    button("Create without the clashing sessions").click();
    await settle();
    expect(createClass).toHaveBeenCalledWith({ request });
    expect(closed.mock.calls[0][0].detail).toEqual({
      classId: "0P0000000000001",
      sessions: 12
    });
  });

  it("will not create a class when every session clashes", async () => {
    previewClass.mockResolvedValue({
      ...PREVIEW,
      sessions: 0,
      firstSessions: [],
      lastSession: null
    });
    const { element, all, button, field } = await setUp({
      courseId: COURSE,
      branchId: BRANCH
    });
    button("Next").click();
    await settle();
    button("Next").click();
    await settle();
    all("button.chip")[5].click();
    await settle();
    button("Next").click();
    await settle();
    expect(element.shadowRoot.textContent).toContain(
      "No sessions can be created"
    );
    expect(button("Create without the clashing sessions").disabled).toBe(true);
    button("Back").click();
    await settle();
    expect(field("startDate")).not.toBeNull();
  });

  it("starts from a preset course and branch and adds faculty inline", async () => {
    createFaculty.mockResolvedValue("003000000000009");
    const { element, button, field, all } = await setUp({
      courseId: COURSE,
      branchId: BRANCH
    });
    expect(field("courseId").value).toBe(COURSE);
    change(field("capacity"), "14");
    await settle();
    button("Next").click();
    await settle();
    // Branch choices were loaded once on open.
    expect(getBranchChoices).toHaveBeenCalledTimes(1);
    change(field("roomId"), ROOM);
    await settle();
    expect(element.shadowRoot.textContent).toContain(
      "Only 10 seats for a class of 14"
    );
    button("Next").click();
    await settle();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("reduce the class size");

    button("New faculty member").click();
    await settle();
    const last = all('lightning-input[data-field="lastName"]')[0];
    last.value = "Pillai";
    last.dispatchEvent(new CustomEvent("change"));
    await settle();
    button("Add and choose").click();
    await settle();
    expect(createFaculty).toHaveBeenCalledWith({
      request: { firstName: "", lastName: "Pillai", email: "", subject: "" }
    });
    expect(getChoices).toHaveBeenCalledTimes(2);
    expect(field("facultyId").value).toBe("003000000000009");
  });
});
