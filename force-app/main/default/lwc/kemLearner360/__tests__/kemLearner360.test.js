import { createElement } from "lwc";
import KemLearner360 from "c/kemLearner360";
import LightningModal from "lightning/modal";
import getLearner360 from "@salesforce/apex/Learner360Controller.getLearner360";
import updatePreferences from "@salesforce/apex/Learner360Controller.updatePreferences";
import getLearnerResults from "@salesforce/apex/AssessmentController.getLearnerResults";
import getLearnerInvoices from "@salesforce/apex/BillingController.getLearnerInvoices";

jest.mock(
  "@salesforce/apex/Learner360Controller.getLearner360",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AssessmentController.getLearnerResults",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/BillingController.getLearnerInvoices",
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

  it("lists published results with grades", async () => {
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.emit(VIEW);
    getLearnerResults.emit([
      {
        Id: "a0R000000000001",
        Course_Assessment__c: "a0Q000000000001",
        Score__c: 47,
        Max_Score__c: 50,
        Percentage__c: 94,
        Grade__c: "A+",
        Absent__c: false,
        Feedback__c: "Excellent work",
        Course_Assessment__r: {
          Name: "Unit test 1",
          Assessment_Type__c: "Test",
          Course_Offering__r: { Name: "Maths Sat AM" }
        }
      }
    ]);
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Unit test 1");
    expect(text).toContain("47 / 50 (94%)");
    expect(text).toContain("Excellent work");
    expect(
      element.shadowRoot.querySelector(".kem-badge_success").textContent
    ).toBeTruthy();
  });

  it("shows invoices with the balance due", async () => {
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.emit(VIEW);
    getLearnerInvoices.emit([
      {
        Id: "a0I000000000001",
        Name: "BLR-000001",
        Status__c: "Partially Paid",
        Balance_Due__c: 4080,
        Overdue__c: true,
        Due_Date__c: "2026-09-30",
        Enrolment__r: { CourseOffering: { Name: "Maths Sat AM" } }
      },
      {
        Id: "a0I000000000002",
        Name: "BLR-000002",
        Status__c: "Paid",
        Balance_Due__c: 0,
        Overdue__c: false
      }
    ]);
    await flush();
    const text = element.shadowRoot.textContent;
    expect(text).toContain("BLR-000001");
    expect(text).toContain("1 overdue");
    expect(element.shadowRoot.querySelector(".fee-balance").value).toBe(4080);
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

  it("opens New application and Portal access for the learner", async () => {
    const element = createElement("c-kem-learner-360", { is: KemLearner360 });
    element.recordId = "001000000000001";
    document.body.appendChild(element);
    getLearner360.emit(VIEW);
    await flush();
    LightningModal.open.mockResolvedValueOnce(null);
    element.shadowRoot
      .querySelector("lightning-button.new-application")
      .click();
    await flush();
    expect(LightningModal.open).toHaveBeenLastCalledWith(
      expect.objectContaining({
        label: "New application",
        learnerId: "001000000000001"
      })
    );
    LightningModal.open.mockResolvedValueOnce(0);
    element.shadowRoot.querySelector("lightning-button.portal-access").click();
    await flush();
    expect(LightningModal.open).toHaveBeenLastCalledWith(
      expect.objectContaining({
        label: "Portal access",
        accountId: "001000000000001"
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
