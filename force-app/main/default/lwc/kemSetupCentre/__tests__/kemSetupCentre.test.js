import { createElement } from "lwc";
import KemSetupCentre from "c/kemSetupCentre";
import getCentre from "@salesforce/apex/SetupCentreController.getCentre";
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
jest.mock(
  "@salesforce/apex/SetupCentreController.getCentre",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const CENTRE = {
  openGaps: 2,
  tiles: [
    {
      key: "branches",
      label: "Branches",
      icon: "custom:custom24",
      count: 3,
      detail: "All active",
      objectApiName: "Branch__c",
      listView: "All",
      canCreate: true,
      createLabel: "New branch"
    },
    {
      key: "courses",
      label: "Courses",
      icon: "standard:education",
      count: 8,
      detail: "Active courses",
      objectApiName: "LearningCourse",
      canCreate: false,
      createLabel: "New course"
    },
    {
      key: "portal",
      label: "Portal access",
      icon: "standard:portal",
      count: 6,
      detail: "Families signed up · 4 licences free",
      objectApiName: null,
      canCreate: false
    }
  ],
  gaps: [
    {
      key: "classTeacher",
      label: "Classes without a teacher",
      advice: "Assign a teacher.",
      count: 7,
      records: [
        { id: "0P0A", name: "Calculus I" },
        { id: "0P0B", name: "Physics" }
      ]
    },
    {
      key: "branchRooms",
      label: "Branches without rooms",
      advice: "Add rooms.",
      count: 1,
      records: [{ id: "a0MA", name: "Bare Centre" }]
    },
    {
      key: "classSeats",
      label: "Classes without a seat limit",
      advice: "Set a limit.",
      count: 0,
      records: []
    }
  ]
};

async function render() {
  const element = createElement("c-kem-set-up-centre", { is: KemSetupCentre });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe("c-kem-setup-centre", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows tiles with create and list actions, and open gaps", async () => {
    getCentre.mockResolvedValue(CENTRE);
    const element = await render();
    const root = element.shadowRoot;
    const tiles = root.querySelectorAll("li.tile");
    expect(tiles).toHaveLength(3);
    expect(tiles[0].textContent).toContain("Branches");
    expect(tiles[0].querySelector(".tile-count").textContent).toBe("3");
    // New only where the user may create; View all only where there is a list.
    expect(tiles[0].querySelector("lightning-button.create").label).toBe(
      "New branch"
    );
    expect(tiles[1].querySelector("lightning-button.create")).toBeNull();
    expect(tiles[2].querySelector("lightning-button.list")).toBeNull();
    expect(root.textContent).toContain("2 to fix");

    const gaps = root.querySelectorAll("li.gap");
    expect(gaps).toHaveLength(2); // gaps with nothing to fix are hidden
    expect(gaps[0].textContent).toContain("and 5 more");

    tiles[0].querySelector("lightning-button.create").click();
    expect(getNavigateCalledWith()).toEqual({
      type: "standard__objectPage",
      attributes: { objectApiName: "Branch__c", actionName: "new" }
    });
    tiles[0].querySelector("lightning-button.list").click();
    expect(getNavigateCalledWith().state).toEqual({ filterName: "All" });
    gaps[1].querySelector("a").click();
    expect(getNavigateCalledWith().attributes.recordId).toBe("a0MA");
  });

  it("says everything is set up when there are no gaps", async () => {
    getCentre.mockResolvedValue({ ...CENTRE, openGaps: 0, gaps: [] });
    const element = await render();
    expect(element.shadowRoot.textContent).toContain("Everything is set up");
    expect(element.shadowRoot.textContent).toContain("All set");
  });

  it("stays hidden for users without access", async () => {
    getCentre.mockRejectedValue({
      body: {
        message:
          "You do not have access to the Apex class named 'SetupCentreController'."
      }
    });
    const element = await render();
    expect(element.shadowRoot.querySelector("article")).toBeNull();
  });
});
