import { createElement } from "lwc";
import KemWaitlistJoinModal from "c/kemWaitlistJoinModal";
import searchLearners from "@salesforce/apex/EnrolmentController.searchLearners";
import joinWaitlist from "@salesforce/apex/WaitlistController.joinWaitlist";

jest.mock(
  "@salesforce/apex/EnrolmentController.searchLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/WaitlistController.joinWaitlist",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-waitlist-join-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("searches, picks a learner and joins with priority", async () => {
    jest.useFakeTimers();
    searchLearners.mockResolvedValue([
      { Id: "001A", Name: "Meera Rao", PersonEmail: "m@example.com" }
    ]);
    joinWaitlist.mockResolvedValue("a0W1");
    const element = createElement("c-kem-waitlist-join-modal", {
      is: KemWaitlistJoinModal
    });
    element.offeringId = "0P0000000000001";
    element.className = "Maths";
    document.body.appendChild(element);

    const search = element.shadowRoot.querySelector("lightning-input");
    search.value = "Mee";
    search.dispatchEvent(new CustomEvent("change"));
    jest.advanceTimersByTime(400);
    jest.useRealTimers();
    await flush();
    await flush();

    element.shadowRoot.querySelector("button.option").click();
    await flush();
    const priority = element.shadowRoot.querySelector("lightning-combobox");
    priority.dispatchEvent(
      new CustomEvent("change", { detail: { value: "1" } })
    );
    const save = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Add to waitlist");
    expect(save.disabled).toBe(false);
    save.click();
    await flush();
    expect(joinWaitlist).toHaveBeenCalledWith({
      request: expect.objectContaining({
        learnerAccountId: "001A",
        offeringId: "0P0000000000001",
        priority: 1
      })
    });
  });
});
