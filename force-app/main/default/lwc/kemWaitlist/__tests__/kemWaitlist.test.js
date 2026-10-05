import { createElement } from "lwc";
import KemWaitlist from "c/kemWaitlist";
import { publish } from "lightning/messageService";
import getWaitlist from "@salesforce/apex/WaitlistController.getWaitlist";
import acceptOffer from "@salesforce/apex/WaitlistController.acceptOffer";
import JoinModal from "c/kemWaitlistJoinModal";

jest.mock(
  "@salesforce/apex/WaitlistController.getWaitlist",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/WaitlistController.acceptOffer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/WaitlistController.declineOffer",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/WaitlistController.removeFromWaitlist",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/WaitlistController.requeue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "c/kemWaitlistJoinModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const VIEW = {
  className: "Maths Sat AM",
  capacity: 3,
  taken: 2,
  reserved: 1,
  available: 0,
  canManage: true,
  entries: [
    {
      id: "a0W1",
      learnerName: "Kavya Iyer",
      learnerAccountId: "001A",
      status: "Offered",
      priority: 1,
      offerExpires: new Date(Date.now() + 5 * 3600000).toISOString()
    },
    {
      id: "a0W2",
      learnerName: "Meera Rao",
      learnerAccountId: "001B",
      status: "Waiting",
      position: 1,
      priority: 0,
      requestedOn: new Date().toISOString()
    },
    {
      id: "a0W3",
      learnerName: "Old Entry",
      status: "Expired",
      priority: 0,
      notes: "Expired"
    }
  ]
};

describe("c-kem-waitlist", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  async function mount() {
    getWaitlist.mockResolvedValue(VIEW);
    const element = createElement("c-kem-waitlist", { is: KemWaitlist });
    element.recordId = "0P0000000000001";
    document.body.appendChild(element);
    await flush();
    return element;
  }

  it("shows seats, queue order, countdown and history", async () => {
    const element = await mount();
    const values = [...element.shadowRoot.querySelectorAll(".seat-value")].map(
      (n) => n.textContent
    );
    expect(values).toEqual(["3", "2", "1", "0", "1"]);
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Reply within 4h");
    expect(text).toContain("#1");
    expect(text).toContain("Priority");
    expect(text).toContain("Show history (1)");
  });

  it("accepts a held seat and announces the change", async () => {
    acceptOffer.mockResolvedValue("0kX000000000001");
    const element = await mount();
    const accept = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Accept seat");
    accept.click();
    await flush();
    await flush();
    expect(acceptOffer).toHaveBeenCalledWith({ entryId: "a0W1" });
    expect(publish).toHaveBeenCalled();
  });

  it("opens the join form with the class name", async () => {
    JoinModal.open.mockResolvedValue(null);
    const element = await mount();
    const add = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Add to waitlist");
    add.click();
    await flush();
    expect(JoinModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        offeringId: "0P0000000000001",
        className: "Maths Sat AM"
      })
    );
  });
});
