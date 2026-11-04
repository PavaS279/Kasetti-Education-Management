import { createElement } from "lwc";
import KemCollegeNewAdmission from "c/kemCollegeNewAdmission";
import AdmissionWizard from "c/kemCollegeAdmissionWizard";

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-college-new-admission", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("opens the guided admission", async () => {
    AdmissionWizard.open.mockResolvedValue(null);
    const element = createElement("c-kem-college-new-admission", {
      is: KemCollegeNewAdmission
    });
    document.body.appendChild(element);
    element.shadowRoot.querySelector("lightning-button").click();
    await flush();
    expect(AdmissionWizard.open).toHaveBeenCalledWith(
      expect.objectContaining({ size: "large" })
    );
  });
});
