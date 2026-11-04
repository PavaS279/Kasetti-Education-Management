import { createElement } from "lwc";
import KemAbsenceModal from "c/kemAbsenceModal";
import recordAbsence from "@salesforce/apex/CoverController.recordAbsence";

jest.mock(
  "@salesforce/apex/CoverController.recordAbsence",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-absence-modal", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("records the user's own absence by default and shows errors", async () => {
    recordAbsence.mockRejectedValue({
      body: {
        message:
          "This teacher already has an absence in that period (ABS-00001)."
      }
    });
    const el = createElement("c-kem-absence-modal", { is: KemAbsenceModal });
    el.canArrange = false;
    document.body.appendChild(el);
    await flush();
    expect(el.shadowRoot.querySelectorAll("lightning-combobox")).toHaveLength(
      1
    );
    [...el.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Report absence")
      .click();
    await flush();
    expect(recordAbsence).toHaveBeenCalledWith({
      request: expect.objectContaining({
        teacherId: null,
        reason: "Sick Leave"
      })
    });
    expect(el.shadowRoot.textContent).toContain("already has an absence");
  });

  it("lets schedulers choose the teacher", async () => {
    recordAbsence.mockResolvedValue("a0S1");
    const el = createElement("c-kem-absence-modal", { is: KemAbsenceModal });
    el.canArrange = true;
    el.teachers = [{ Id: "005B", Name: "Bina" }];
    document.body.appendChild(el);
    await flush();
    const combos = el.shadowRoot.querySelectorAll("lightning-combobox");
    expect(combos).toHaveLength(2);
    combos[0].dispatchEvent(
      new CustomEvent("change", { detail: { value: "005B" } })
    );
    await flush();
    [...el.shadowRoot.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Report absence")
      .click();
    await flush();
    expect(recordAbsence).toHaveBeenCalledWith({
      request: expect.objectContaining({ teacherId: "005B" })
    });
  });
});
