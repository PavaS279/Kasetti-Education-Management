import { createElement } from "lwc";
import KemLearner360 from "c/kemLearner360";
import getLearner360 from "@salesforce/apex/Learner360Controller.getLearner360";
import updatePreferences from "@salesforce/apex/Learner360Controller.updatePreferences";

jest.mock(
  "@salesforce/apex/Learner360Controller.getLearner360",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.endGuardianLink",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.updatePreferences",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.addGuardian",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.updateGuardianLink",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.searchPeople",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const VIEW = {
  isLearner: true,
  isGuardian: false,
  person: {
    Id: "001000000000001",
    Name: "Ananya Sharma",
    IsPersonAccount: true,
    PersonEmail: "ananya@example.com",
    PersonMobilePhone: "+919900112233",
    KEM_Role__c: "Learner",
    Branch__r: { Name: "Bengaluru Central" },
    Emergency_Instructions__pc: "Peanut allergy",
    Preferred_Channel__pc: "WhatsApp"
  },
  profile: { Student_Number__c: "STU-00042" },
  guardians: [
    {
      relationId: "0RE000000000001",
      accountId: "001000000000002",
      name: "Rohit Sharma",
      relationship: "Father",
      isFeePayer: true,
      portalAccess: true,
      isEmergencyContact: false
    }
  ],
  children: [],
  siblings: [{ accountId: "001000000000003", name: "Arjun Sharma" }],
  applications: [
    {
      Id: "0iT000000000001",
      Name: "IA-0001",
      Status: "Processing",
      Learning_Course__r: { Name: "Maths" }
    }
  ],
  enrolments: [
    {
      Id: "0kX000000000001",
      Name: "E1",
      ParticipationStatus: "Enrolled",
      CourseOffering: { Name: "Maths Sat AM" }
    }
  ]
};

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-learner-360", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the learner hero, guardians, siblings, and emergency alert", async () => {
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.emit(VIEW);
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Ananya Sharma");
    expect(text).toContain("STU-00042");
    expect(text).toContain("Rohit Sharma");
    expect(text).toContain("Arjun Sharma");
    expect(text).toContain("Peanut allergy");
    const kpis = [
      ...element.shadowRoot.querySelectorAll(".kem-kpi__value")
    ].map((n) => n.textContent);
    expect(kpis).toEqual(["1", "1", "1"]);
  });

  it("saves communication preferences", async () => {
    updatePreferences.mockResolvedValue(undefined);
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.emit(VIEW);
    await flush();
    const save = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Save preferences");
    save.click();
    await flush();
    expect(updatePreferences).toHaveBeenCalledWith(
      expect.objectContaining({
        accountId: "001000000000001",
        input: expect.objectContaining({ preferredChannel: "WhatsApp" })
      })
    );
  });

  it("shows an error when the record cannot be loaded", async () => {
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.error({ message: "No access" });
    await flush();
    expect(
      element.shadowRoot.querySelector(".slds-alert_error")
    ).not.toBeNull();
  });
});
