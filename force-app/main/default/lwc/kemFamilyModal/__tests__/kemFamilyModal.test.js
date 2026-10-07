import { createElement } from "lwc";
import KemFamilyModal from "c/kemFamilyModal";
import getChoices from "@salesforce/apex/FamilySetupController.getChoices";
import findMatches from "@salesforce/apex/FamilySetupController.findMatches";
import createFamily from "@salesforce/apex/FamilySetupController.createFamily";

jest.mock(
  "@salesforce/apex/FamilySetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FamilySetupController.findMatches",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FamilySetupController.createFamily",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const BRANCH = "a0M000000000001";
const COURSE = "0ZV000000000001";
const CLASS = "0P0000000000001";
const EXISTING = "001000000000EXI";

const CHOICES = {
  branches: [{ label: "KT Edutech Indiranagar", value: BRANCH }],
  courses: [{ label: "Python for Kids", value: COURSE, detail: "Ages 9–13" }],
  classes: [
    {
      label: "Python for Kids – Saturday 12:00 (2 seats free)",
      value: CLASS,
      detail: COURSE
    }
  ],
  defaultBranchId: BRANCH,
  canEnrol: true,
  canApply: true
};

const setUp = async () => {
  getChoices.mockResolvedValue(CHOICES);
  const element = createElement("c-kem-family-modal", { is: KemFamilyModal });
  const closed = jest.fn();
  element.addEventListener("close", closed);
  document.body.appendChild(element);
  await settle();
  const root = element.shadowRoot;
  const valid = () =>
    root
      .querySelectorAll("lightning-input, lightning-combobox")
      .forEach((i) => {
        i.reportValidity = () => true;
      });
  const button = (label) =>
    [...root.querySelectorAll("lightning-button")].find(
      (b) => b.label === label
    );
  const at = (index, field) =>
    root.querySelector(`[data-index="${index}"][data-field="${field}"]`);
  const next = async () => {
    valid();
    button("Next").click();
    await settle();
  };
  return { element, root, button, at, next, closed };
};
const change = async (el, value) => {
  el.value = value;
  if (typeof value === "boolean") {
    el.checked = value;
  }
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await settle();
};

describe("c-kem-family-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("collects parents and children, finds an existing parent and saves the family", async () => {
    findMatches.mockResolvedValue([
      {
        kind: "guardian",
        index: 0,
        accountId: EXISTING,
        name: "Kavya Rao",
        detail: "Guardian · kavya@example.com"
      }
    ]);
    createFamily.mockResolvedValue({
      learnerIds: ["001L1", "001L2"],
      guardianIds: [EXISTING],
      enrolmentIds: ["0eP1"],
      applicationIds: ["0iT1"],
      created: 2,
      reused: 1
    });
    const { root, button, at, next, closed } = await setUp();
    expect(root.querySelector('[data-field="branchId"]').value).toBe(BRANCH);

    await change(at(0, "firstName"), "Kavya");
    await change(at(0, "lastName"), "Rao");
    await change(at(0, "email"), "kavya@example.com");
    // The father is left empty and skipped; tick the mother as fee payer.
    await change(at(0, "isFeePayer"), true);
    await next();

    // The family name carries over to the child.
    expect(at(0, "lastName").value).toBe("Rao");
    await change(at(0, "firstName"), "Aditi");
    await change(at(0, "birthdate"), "2015-06-01");
    await change(at(0, "nextStep"), "enrol");
    await change(at(0, "offeringId"), CLASS);
    button("Add another child").click();
    await settle();
    await change(at(1, "firstName"), "Arjun");
    await change(at(1, "birthdate"), "2018-02-11");
    await change(at(1, "nextStep"), "apply");
    await change(at(1, "courseId"), COURSE);
    await next();

    const checked = findMatches.mock.calls[0][0].request;
    expect(checked.guardians).toHaveLength(1);
    expect(checked.guardians[0]).toMatchObject({
      lastName: "Rao",
      isFeePayer: true
    });
    expect(checked.learners[0]).toMatchObject({
      firstName: "Aditi",
      nextStep: "enrol",
      offeringId: CLASS,
      courseId: null
    });
    expect(checked.learners[1]).toMatchObject({
      firstName: "Arjun",
      nextStep: "apply",
      courseId: COURSE,
      offeringId: null
    });
    expect(root.textContent).toContain("Kavya Rao");
    expect(root.textContent).toContain("1 enrolled now");

    button("Use existing").click();
    await settle();
    expect(button("Using existing")).toBeTruthy();
    expect(root.textContent).toContain("1 already on file");
    button("Save the family").click();
    await settle();
    expect(
      createFamily.mock.calls[0][0].request.guardians[0].existingAccountId
    ).toBe(EXISTING);
    expect(closed.mock.calls[0][0].detail.learnerIds).toEqual([
      "001L1",
      "001L2"
    ]);
  });

  it("explains what is missing before moving on", async () => {
    findMatches.mockResolvedValue([]);
    createFamily.mockRejectedValue({
      body: { message: "Python for Kids – Saturday 12:00 is full." }
    });
    const { root, button, at, next } = await setUp();
    await change(at(0, "lastName"), "Rao");
    await next();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "email or mobile"
    );
    await change(at(0, "phone"), "+91 98450 12345");
    await next();
    await change(at(0, "firstName"), "Aditi");
    await next();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "date of birth"
    );
    await change(at(0, "birthdate"), "2015-06-01");
    await change(at(0, "nextStep"), "enrol");
    await next();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "Choose the class"
    );
    await change(at(0, "nextStep"), "none");
    await next();
    expect(root.textContent).toContain("Nobody here is on file yet");
    button("Save the family").click();
    await settle();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "is full"
    );
  });
});
