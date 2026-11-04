import { createElement } from "lwc";
import KemClassAssessments from "c/kemClassAssessments";
import { getNavigateCalledWith } from "lightning/navigation";

jest.mock(
  "lightning/navigation",
  () => {
    const Navigate = Symbol("Navigate");
    let last;
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](pageRef) {
          last = pageRef;
        }
      };
    NavigationMixin.Navigate = Navigate;
    return {
      __esModule: true,
      NavigationMixin,
      getNavigateCalledWith: () => last
    };
  },
  { virtual: true }
);
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import getClassAssessments from "@salesforce/apex/AssessmentController.getClassAssessments";

jest.mock(
  "@salesforce/apex/AssessmentController.getClassAssessments",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-class-assessments", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists assessments and opens one", async () => {
    getClassAssessments.mockResolvedValue([
      {
        Id: "a0Q000000000001",
        Name: "Unit test 1",
        Assessment_Type__c: "Test",
        Max_Score__c: 50,
        Status__c: "Published",
        Average_Percentage__c: 78
      }
    ]);
    const element = createElement("c-kem-class-assessments", {
      is: KemClassAssessments
    });
    element.recordId = "0kA000000000001";
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("78% avg");
    element.shadowRoot.querySelector("button.item").click();
    expect(getNavigateCalledWith().attributes.recordId).toBe("a0Q000000000001");
  });

  it("creates a new assessment for the class", async () => {
    getClassAssessments.mockResolvedValue([]);
    const element = createElement("c-kem-class-assessments", {
      is: KemClassAssessments
    });
    element.recordId = "0kA000000000001";
    document.body.appendChild(element);
    await flush();
    expect(element.shadowRoot.textContent).toContain("No assessments yet");
    element.shadowRoot.querySelector("lightning-button").click();
    const page = getNavigateCalledWith();
    expect(page.attributes).toEqual({
      objectApiName: "Course_Assessment__c",
      actionName: "new"
    });
    expect(encodeDefaultFieldValues).toHaveBeenCalledWith({
      Course_Offering__c: "0kA000000000001",
      Grade_Scale__c: "Standard"
    });
  });
});
