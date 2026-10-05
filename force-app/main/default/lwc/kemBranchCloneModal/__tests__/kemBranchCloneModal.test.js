import { createElement } from "lwc";
import KemBranchCloneModal from "c/kemBranchCloneModal";
import getTemplatePreview from "@salesforce/apex/BranchController.getTemplatePreview";
import cloneBranch from "@salesforce/apex/BranchController.cloneBranch";

jest.mock(
  "@salesforce/apex/BranchController.getTemplatePreview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BranchController.cloneBranch",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

function preview(overrides = {}) {
  return {
    branchId: "a00000000000001",
    name: "Indiranagar",
    code: "BLR-01",
    rooms: 3,
    prices: 4,
    discounts: 1,
    closures: 2,
    classes: 5,
    patterns: 6,
    suggestedStart: "2026-11-01",
    canCreate: true,
    ...overrides
  };
}

function render() {
  const element = createElement("c-kem-branch-clone-modal", {
    is: KemBranchCloneModal
  });
  element.branchId = "a00000000000001";
  document.body.appendChild(element);
  return element;
}

const inputs = (element) => [
  ...element.shadowRoot.querySelectorAll("lightning-input")
];
const field = (element, name) =>
  inputs(element).find((i) => i.dataset.field === name);
const button = (element, label) =>
  [...element.shadowRoot.querySelectorAll("lightning-button")].find(
    (b) => b.label === label
  );

function type(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

describe("c-kem-branch-clone-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows what will be copied and opens the branch", async () => {
    getTemplatePreview.mockResolvedValue(preview());
    cloneBranch.mockResolvedValue({
      branchId: "a00000000000009",
      branchName: "Whitefield",
      rooms: 3,
      prices: 4,
      discounts: 1,
      closures: 2,
      classes: 5,
      patterns: 6,
      notes: ["Assign teachers to the new classes."]
    });
    const element = render();
    await flush();
    expect(
      element.shadowRoot.querySelector("lightning-modal-header").label
    ).toBe("New branch from Indiranagar");
    const parts = element.shadowRoot.querySelectorAll(".part");
    expect(parts.length).toBe(5);
    expect(parts[4].textContent).toContain("5 · 6 patterns");
    expect(field(element, "classStartDate").value).toBe("2026-11-01");
    expect(button(element, "Open branch").disabled).toBe(true);

    type(field(element, "name"), "Whitefield");
    type(field(element, "code"), "wfd-01");
    type(field(element, "invoicePrefix"), "wfd");
    type(field(element, "city"), "Bengaluru");
    const prices = field(element, "includePrices");
    prices.checked = false;
    prices.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(button(element, "Open branch").disabled).toBe(false);

    button(element, "Open branch").click();
    await flush();
    expect(cloneBranch).toHaveBeenCalledWith({
      request: expect.objectContaining({
        sourceBranchId: "a00000000000001",
        name: "Whitefield",
        code: "WFD-01",
        invoicePrefix: "WFD",
        city: "Bengaluru",
        includePrices: false,
        includeClasses: true,
        classStartDate: "2026-11-01"
      })
    });
    expect(element.shadowRoot.querySelector(".success").textContent).toContain(
      "Whitefield is ready."
    );
    expect(element.shadowRoot.querySelectorAll(".stat").length).toBe(6);
    expect(element.shadowRoot.querySelector(".notes").textContent).toContain(
      "Assign teachers"
    );
    expect(button(element, "Open new branch")).toBeTruthy();
  });

  it("hides the start date without classes and shows server errors", async () => {
    getTemplatePreview.mockResolvedValue(preview());
    cloneBranch.mockRejectedValue({
      body: { message: "Branch code WFD-01 is already used by Whitefield." }
    });
    const element = render();
    await flush();
    const classes = field(element, "includeClasses");
    classes.checked = false;
    classes.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(field(element, "classStartDate")).toBeUndefined();
    type(field(element, "name"), "Whitefield");
    type(field(element, "code"), "WFD-01");
    type(field(element, "invoicePrefix"), "WFD");
    await flush();
    button(element, "Open branch").click();
    await flush();
    expect(cloneBranch.mock.calls[0][0].request.classStartDate).toBe(
      "2026-11-01"
    );
    expect(
      element.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("already used");
  });

  it("explains when the user cannot open branches", async () => {
    getTemplatePreview.mockResolvedValue(preview({ canCreate: false }));
    const element = render();
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_warning").textContent
    ).toContain("Only administrators");
    type(field(element, "name"), "X");
    type(field(element, "code"), "X");
    type(field(element, "invoicePrefix"), "X");
    await flush();
    expect(button(element, "Open branch").disabled).toBe(true);
  });

  it("shows a load error", async () => {
    getTemplatePreview.mockRejectedValue({ body: { message: "Not found" } });
    const element = render();
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_error").textContent
    ).toContain("Not found");
    button(element, "Cancel").click();
  });
});
