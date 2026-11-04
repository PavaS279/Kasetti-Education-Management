import { createElement } from "lwc";
import KemCourseWizardModal from "c/kemCourseWizardModal";
import getChoices from "@salesforce/apex/CatalogSetupController.getChoices";
import createCourse from "@salesforce/apex/CatalogSetupController.createCourse";

jest.mock(
  "@salesforce/apex/CatalogSetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CatalogSetupController.createCourse",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const CHOICES = {
  canPrice: true,
  branches: [{ label: "KT Edutech Indiranagar", value: "a0M000000000001" }],
  courses: [],
  faculty: []
};

const setUp = async (choices = CHOICES) => {
  getChoices.mockResolvedValue(choices);
  const element = createElement("c-kem-course-wizard-modal", {
    is: KemCourseWizardModal
  });
  document.body.appendChild(element);
  await flush();
  await flush();
  const all = (sel) => [...element.shadowRoot.querySelectorAll(sel)];
  all("lightning-input, lightning-combobox").forEach((i) => {
    i.reportValidity = () => true;
  });
  const button = (label) =>
    all("lightning-button").find((b) => b.label === label);
  const field = (name) =>
    element.shadowRoot.querySelector(
      `[data-field="${name}"]:not([data-index])`
    );
  const line = (index, name) =>
    element.shadowRoot.querySelector(
      `[data-index="${index}"][data-field="${name}"]`
    );
  return { element, all, button, field, line };
};

const type = (input, value) => {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};

describe("c-kem-course-wizard-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("creates the course with its priced lines and offers a class next", async () => {
    createCourse.mockResolvedValue("0ZV000000000001");
    const { element, button, field, line, all } = await setUp();
    const closed = jest.fn();
    element.addEventListener("close", closed);
    expect(button("Create course").disabled).toBe(true);
    type(field("name"), "Chess for Beginners");
    type(field("code"), "KT-CRS-CHS");
    type(field("minAge"), "7");
    type(field("maxAge"), "12");
    type(line(0, "amount"), "2500");
    type(line(0, "branchId"), "a0M000000000001");
    await flush();
    // The admission line has no amount, so it is skipped.
    button("Add price").click();
    await flush();
    expect(all("li.price")).toHaveLength(3);
    all("lightning-input, lightning-combobox").forEach((i) => {
      i.reportValidity = () => true;
    });
    button("Create and add a class").click();
    await flush();
    const request = createCourse.mock.calls[0][0].request;
    expect(request).toMatchObject({
      name: "Chess for Beginners",
      code: "KT-CRS-CHS",
      minAge: 7,
      maxAge: 12
    });
    expect(request.prices).toEqual([
      {
        feeType: "Tuition",
        frequency: "Monthly",
        amount: 2500,
        branchId: "a0M000000000001"
      }
    ]);
    expect(closed.mock.calls[0][0].detail).toEqual({
      courseId: "0ZV000000000001",
      addClass: true
    });
  });

  it("warns without tuition and hides prices from people who cannot set them", async () => {
    const { element, line, all } = await setUp();
    expect(element.shadowRoot.textContent).toContain("No tuition amount yet");
    type(line(0, "amount"), "1800");
    await flush();
    expect(element.shadowRoot.textContent).not.toContain(
      "No tuition amount yet"
    );
    all("lightning-button-icon")[0].click();
    await flush();
    expect(all("li.price")).toHaveLength(1);

    document.body.removeChild(element);
    const second = await setUp({ ...CHOICES, canPrice: false });
    expect(second.all("li.price")).toHaveLength(0);
    expect(second.element.shadowRoot.textContent).toContain(
      "Prices are set by finance"
    );
  });

  it("shows why a course was refused", async () => {
    createCourse.mockRejectedValue({
      body: { message: "Course code KT-CRS-CHS is already used." }
    });
    const { element, button, field } = await setUp();
    type(field("name"), "Chess");
    await flush();
    button("Create course").click();
    await flush();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("already used");
  });
});
