import { createElement } from "lwc";
import KemPortalAccessModal from "c/kemPortalAccessModal";
import getFamily from "@salesforce/apex/PortalAccessController.getFamily";
import prepareAccess from "@salesforce/apex/PortalAccessController.prepareAccess";
import giveAccess from "@salesforce/apex/PortalAccessController.giveAccess";
import searchPeople from "@salesforce/apex/Learner360Controller.searchPeople";

jest.mock(
  "@salesforce/apex/PortalAccessController.getFamily",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalAccessController.prepareAccess",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/PortalAccessController.giveAccess",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/Learner360Controller.searchPeople",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);

const FAMILY = (hasLogin) => ({
  canGive: true,
  freeLicences: hasLogin ? 3 : 4,
  portalUrl: "https://kasettitechnologiespvtltd.my.site.com/s/my-learning",
  people: [
    {
      accountId: "001G",
      name: "Priya Nair",
      role: "Guardian",
      email: "priya@example.com",
      hasLogin,
      active: hasLogin,
      username: hasLogin
        ? "priya@example.com.kasettitechnologiespvtltd.portal"
        : null,
      canGive: !hasLogin,
      reason: hasLogin ? "Has a portal login" : null
    },
    {
      accountId: "001C",
      name: "Diya Nair",
      role: "Learner",
      hasLogin: false,
      canGive: false,
      reason: "Under 13: uses a guardian's login"
    }
  ]
});

describe("c-kem-portal-access-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("gives a parent access and shows why a child cannot have it", async () => {
    getFamily
      .mockResolvedValueOnce(FAMILY(false))
      .mockResolvedValueOnce(FAMILY(true));
    prepareAccess.mockResolvedValue(false);
    giveAccess.mockResolvedValue({
      userId: "005P",
      username: "priya@example.com.kasettitechnologiespvtltd.portal",
      emailSent: true
    });
    const element = createElement("c-kem-portal-access-modal", {
      is: KemPortalAccessModal
    });
    element.accountId = "001C";
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    expect(root.textContent).toContain("4 portal licences free");
    expect(root.textContent).toContain("Under 13");
    const give = [...root.querySelectorAll("lightning-button")].filter(
      (b) => b.label === "Give access"
    );
    expect(give).toHaveLength(1);
    give[0].click();
    await settle();
    expect(prepareAccess).toHaveBeenCalledWith({ accountId: "001G" });
    expect(giveAccess).toHaveBeenCalledWith({ accountId: "001G" });
    expect(root.textContent).toContain("welcome email");
    expect(root.textContent).toContain("Has a login");
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Done")
      .click();
    expect(closed.mock.calls[0][0].detail).toBe(1);
  });

  it("finds the family first when opened without a person", async () => {
    searchPeople.mockResolvedValue([
      {
        Id: "001G",
        Name: "Priya Nair",
        KEM_Role__c: "Guardian",
        PersonEmail: "priya@example.com"
      }
    ]);
    const noRight = FAMILY(false);
    getFamily.mockResolvedValue({
      ...noRight,
      canGive: false,
      people: noRight.people.map((p) => ({ ...p, canGive: false }))
    });
    const element = createElement("c-kem-portal-access-modal", {
      is: KemPortalAccessModal
    });
    document.body.appendChild(element);
    await settle();
    const root = element.shadowRoot;
    const search = root.querySelector("lightning-input");
    search.value = "pri";
    search.dispatchEvent(new CustomEvent("change"));
    await settle();
    root.querySelector("button.result").click();
    await settle();
    expect(getFamily).toHaveBeenCalledWith({ accountId: "001G" });
    expect(root.textContent).toContain("KEM Manage Portal");
    expect(
      [...root.querySelectorAll("lightning-button")].some(
        (b) => b.label === "Give access"
      )
    ).toBe(false);
    [...root.querySelectorAll("lightning-button")]
      .find((b) => b.label === "Another family")
      .click();
    await settle();
    expect(root.querySelector("lightning-input")).not.toBeNull();
  });
});
