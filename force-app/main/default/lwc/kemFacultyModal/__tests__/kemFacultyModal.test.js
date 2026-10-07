import { createElement } from "lwc";
import KemFacultyModal from "c/kemFacultyModal";
import createFaculty from "@salesforce/apex/CatalogSetupController.createFaculty";

jest.mock(
  "@salesforce/apex/CatalogSetupController.createFaculty",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const type = (input, value) => {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
};

describe("c-kem-faculty-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  const setUp = async () => {
    const element = createElement("c-kem-faculty-modal", {
      is: KemFacultyModal
    });
    document.body.appendChild(element);
    await flush();
    element.shadowRoot.querySelectorAll("lightning-input").forEach((i) => {
      i.reportValidity = () => true;
    });
    const field = (name) =>
      element.shadowRoot.querySelector(`lightning-input[data-field="${name}"]`);
    const add = () =>
      [...element.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Add faculty member"
      );
    return { element, field, add };
  };

  it("needs a last name, then adds the teacher", async () => {
    createFaculty.mockResolvedValue("003000000000001");
    const { element, field, add } = await setUp();
    const closed = jest.fn();
    element.addEventListener("close", closed);
    expect(add().disabled).toBe(true);
    type(field("firstName"), "Meera");
    type(field("lastName"), " Pillai ");
    type(field("email"), "meera@example.com");
    type(field("subject"), "Robotics");
    await flush();
    expect(add().disabled).toBe(false);
    add().click();
    await flush();
    expect(createFaculty).toHaveBeenCalledWith({
      request: {
        firstName: "Meera",
        lastName: "Pillai",
        email: "meera@example.com",
        phone: "",
        subject: "Robotics"
      }
    });
    expect(closed.mock.calls[0][0].detail).toBe("003000000000001");
  });

  it("shows a duplicate email refusal", async () => {
    createFaculty.mockRejectedValue({
      body: {
        message: "A faculty member with meera@example.com already exists."
      }
    });
    const { element, field, add } = await setUp();
    type(field("lastName"), "Pillai");
    await flush();
    add().click();
    await flush();
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("already exists");
  });
});
