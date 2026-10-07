import { createElement } from "lwc";
import KemApplicationModal from "c/kemApplicationModal";
import getChoices from "@salesforce/apex/FamilySetupController.getChoices";
import createApplication from "@salesforce/apex/FamilySetupController.createApplication";

jest.mock(
  "@salesforce/apex/FamilySetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FamilySetupController.createApplication",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);

describe("c-kem-application-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("creates an application with a preferred class of the chosen course", async () => {
    getChoices.mockResolvedValue({
      branches: [{ label: "Indiranagar", value: "a0M1" }],
      courses: [
        { label: "Python for Kids", value: "0ZV1", detail: "Ages 9–13" },
        { label: "Abacus", value: "0ZV2" }
      ],
      classes: [
        { label: "Python – Sat", value: "0P01", detail: "0ZV1" },
        { label: "Abacus – Wed", value: "0P02", detail: "0ZV2" }
      ]
    });
    createApplication.mockResolvedValue("0iT000000000001");
    const element = createElement("c-kem-application-modal", {
      is: KemApplicationModal
    });
    element.learnerId = "001L1";
    element.learnerName = "Ishita Menon";
    element.branchId = "a0M1";
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const boxes = () => root.querySelectorAll("lightning-combobox");
    const save = () =>
      [...root.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Create application"
      );
    expect(save().disabled).toBe(true);
    const pick = async (el, value) => {
      el.value = value;
      el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
      await settle();
    };
    await pick(boxes()[1], "0ZV1");
    // Only the chosen course's classes are offered.
    expect(boxes()[2].options.map((o) => o.value)).toEqual(["", "0P01"]);
    await pick(boxes()[2], "0P01");
    save().click();
    await settle();
    expect(createApplication).toHaveBeenCalledWith({
      learnerId: "001L1",
      branchId: "a0M1",
      courseId: "0ZV1",
      offeringId: "0P01"
    });
    expect(closed.mock.calls[0][0].detail).toBe("0iT000000000001");
  });
});
