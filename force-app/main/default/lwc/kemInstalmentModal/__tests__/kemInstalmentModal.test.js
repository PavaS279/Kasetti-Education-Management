import { createElement } from "lwc";
import KemInstalmentModal from "c/kemInstalmentModal";
import previewInstalmentPlan from "@salesforce/apex/BillingController.previewInstalmentPlan";
import createInstalmentPlan from "@salesforce/apex/BillingController.createInstalmentPlan";

jest.mock(
  "@salesforce/apex/BillingController.previewInstalmentPlan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.createInstalmentPlan",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const PLAN = [
  { sequence: 1, dueDate: "2026-10-15", amount: 1180 },
  { sequence: 2, dueDate: "2026-11-15", amount: 1180 },
  { sequence: 3, dueDate: "2026-12-15", amount: 1180 }
];

async function mount() {
  const element = createElement("c-kem-instalment-modal", {
    is: KemInstalmentModal
  });
  element.invoiceId = "a0I000000000001";
  element.invoiceNumber = "BLR-000010";
  element.total = 3540;
  element.dueDate = "2026-10-15";
  document.body.appendChild(element);
  await flush();
  return element;
}

const button = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

describe("c-kem-instalment-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("previews the schedule from the invoice due date", async () => {
    previewInstalmentPlan.mockResolvedValue(PLAN);
    const element = await mount();
    expect(previewInstalmentPlan).toHaveBeenCalledWith({
      request: {
        invoiceId: "a0I000000000001",
        count: 3,
        firstDueDate: "2026-10-15",
        intervalMonths: 1
      }
    });
    expect(element.shadowRoot.querySelectorAll("tbody tr")).toHaveLength(3);
    expect(button(element, "Create plan").disabled).toBe(false);
  });

  it("re-previews when the count changes and saves the plan", async () => {
    previewInstalmentPlan.mockResolvedValue(PLAN);
    createInstalmentPlan.mockResolvedValue(undefined);
    const element = await mount();
    const combo = element.shadowRoot.querySelector("lightning-combobox");
    combo.dispatchEvent(new CustomEvent("change", { detail: { value: "4" } }));
    await flush();
    expect(previewInstalmentPlan).toHaveBeenLastCalledWith({
      request: expect.objectContaining({ count: 4 })
    });
    button(element, "Create plan").click();
    await flush();
    expect(createInstalmentPlan).toHaveBeenCalled();
  });

  it("shows validation errors and blocks saving", async () => {
    previewInstalmentPlan.mockRejectedValue({
      body: {
        message: "The first instalment cannot be due before the invoice date."
      }
    });
    const element = await mount();
    expect(element.shadowRoot.textContent).toContain("cannot be due before");
    expect(button(element, "Create plan").disabled).toBe(true);
  });
});
