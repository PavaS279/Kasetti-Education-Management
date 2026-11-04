import { createElement } from "lwc";
import KemSessionCover from "c/kemSessionCover";
import { getRecord } from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import getCandidates from "@salesforce/apex/CoverController.getCandidates";
import getRoomOptions from "@salesforce/apex/CoverController.getRoomOptions";
import assignCover from "@salesforce/apex/CoverController.assignCover";
import swapRoom from "@salesforce/apex/CoverController.swapRoom";

jest.mock(
  "@salesforce/apex/CoverController.getCandidates",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.getRoomOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.assignCover",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CoverController.swapRoom",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const RECORD = {
  apiName: "Class_Session__c",
  fields: {
    Status__c: { value: "Scheduled" },
    Needs_Cover__c: { value: true },
    Teacher_User__r: { value: { fields: { Name: { value: "Arun" } } } },
    Original_Teacher__r: { value: null },
    Room__r: { value: { fields: { Name: { value: "R1" } } } },
    Original_Room__r: { value: null },
    Cover_Note__c: { value: null }
  }
};
const INFO = {
  fields: {
    Teacher_User__c: { updateable: true },
    Room__c: { updateable: true }
  }
};

async function mount() {
  const el = createElement("c-kem-session-cover", { is: KemSessionCover });
  el.recordId = "a0X1";
  document.body.appendChild(el);
  getRecord.emit(RECORD);
  getObjectInfo.emit(INFO);
  await flush();
  return el;
}
const buttons = (el) => [...el.shadowRoot.querySelectorAll("lightning-button")];

describe("c-kem-session-cover", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("flags a session needing cover and assigns a suggested teacher", async () => {
    getCandidates.mockResolvedValue([
      {
        userId: "005B",
        name: "Bina",
        free: true,
        taughtCourse: true,
        sessionsThatDay: 0
      },
      { userId: "005C", name: "Chetan", free: false, clash: "Teaching Art" }
    ]);
    assignCover.mockResolvedValue(undefined);
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("needs cover");
    buttons(el)
      .find((b) => b.label === "Find cover")
      .click();
    await flush();
    const assign = buttons(el).filter((b) => b.label === "Assign");
    expect(assign).toHaveLength(2);
    expect(assign[1].disabled).toBe(true);
    assign[0].click();
    await flush();
    expect(assignCover).toHaveBeenCalledWith({
      sessionId: "a0X1",
      coverUserId: "005B",
      note: null
    });
  });

  it("moves the session to a free room", async () => {
    getRoomOptions.mockResolvedValue([
      {
        roomId: "a0R2",
        name: "R2",
        free: true,
        bigEnough: true,
        capacity: 20,
        roomType: "Classroom"
      },
      { roomId: "a0R3", name: "R3", free: true, bigEnough: false, capacity: 1 }
    ]);
    swapRoom.mockResolvedValue(undefined);
    const el = await mount();
    buttons(el)
      .find((b) => b.label === "Change room")
      .click();
    await flush();
    expect(el.shadowRoot.textContent).toContain("too small");
    buttons(el)
      .find((b) => b.label === "Move")
      .click();
    await flush();
    expect(swapRoom).toHaveBeenCalledWith({
      sessionId: "a0X1",
      roomId: "a0R2",
      note: null
    });
  });

  it("hides changes from users who cannot arrange cover", async () => {
    const el = createElement("c-kem-session-cover", { is: KemSessionCover });
    el.recordId = "a0X1";
    document.body.appendChild(el);
    getRecord.emit(RECORD);
    getObjectInfo.emit({
      fields: {
        Teacher_User__c: { updateable: false },
        Room__c: { updateable: false }
      }
    });
    await flush();
    expect(buttons(el)).toHaveLength(0);
  });
});
