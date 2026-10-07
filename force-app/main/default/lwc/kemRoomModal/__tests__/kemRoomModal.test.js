import { createElement } from "lwc";
import KemRoomModal from "c/kemRoomModal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import addRooms from "@salesforce/apex/SiteSetupController.addRooms";

jest.mock(
  "@salesforce/apex/SiteSetupController.getChoices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/SiteSetupController.addRooms",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));
const settle = () => flush().then(flush).then(flush);
const BRANCH = "a0M000000000001";

const valid = (root) => {
  root.querySelectorAll("lightning-input, lightning-combobox").forEach((i) => {
    i.reportValidity = () => true;
  });
};
const change = (el, value) => {
  el.value = value;
  el.dispatchEvent(new CustomEvent("change", { detail: { value } }));
};

describe("c-kem-room-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("adds named rooms to the only branch, with a meeting link for virtual rooms", async () => {
    getChoices.mockResolvedValue({
      branches: [{ label: "KT Edutech Indiranagar", value: BRANCH }]
    });
    addRooms.mockResolvedValue(2);
    const element = createElement("c-kem-room-modal", { is: KemRoomModal });
    const closed = jest.fn();
    element.addEventListener("close", closed);
    document.body.appendChild(element);
    await settle();
    const lines = () =>
      element.shadowRoot.querySelector("c-kem-room-lines").shadowRoot;
    const save = () =>
      [...element.shadowRoot.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Add rooms"
      );
    expect(element.shadowRoot.querySelector("lightning-combobox").value).toBe(
      BRANCH
    );
    expect(save().disabled).toBe(true);

    change(lines().querySelector('[data-field="name"]'), "Turing Lab");
    await settle();
    change(lines().querySelector('[data-field="capacity"]'), "10");
    await settle();
    [...lines().querySelectorAll("lightning-button")]
      .find((b) => b.label === "Add another room")
      .click();
    await settle();
    const names = lines().querySelectorAll('[data-field="name"]');
    change(names[1], "Online Room");
    await settle();
    change(lines().querySelectorAll('[data-field="roomType"]')[1], "Virtual");
    await settle();
    change(lines().querySelectorAll('[data-field="capacity"]')[1], "30");
    await settle();
    change(
      lines().querySelector('[data-field="meetingUrl"]'),
      "https://meet.example.com/kt"
    );
    await settle();
    expect(lines().textContent).toContain("2 rooms · 40 seats");
    valid(lines());
    save().click();
    await settle();
    expect(addRooms).toHaveBeenCalledWith({
      branchId: BRANCH,
      rooms: [
        {
          name: "Turing Lab",
          roomType: "Classroom",
          capacity: 10,
          equipment: "",
          meetingUrl: ""
        },
        {
          name: "Online Room",
          roomType: "Virtual",
          capacity: 30,
          equipment: "",
          meetingUrl: "https://meet.example.com/kt"
        }
      ]
    });
    expect(closed.mock.calls[0][0].detail).toBe(2);
  });
});
