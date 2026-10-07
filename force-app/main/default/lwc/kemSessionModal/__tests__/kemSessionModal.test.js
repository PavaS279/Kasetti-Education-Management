import { createElement } from "lwc";
import KemSessionModal from "c/kemSessionModal";
import addSession from "@salesforce/apex/TimetableController.addSession";

jest.mock(
  "@salesforce/apex/TimetableController.addSession",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

describe("c-kem-session-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("adds a make-up session and shows a clash", async () => {
    addSession
      .mockRejectedValueOnce({
        body: { message: "The room is already booked for Python for Kids." }
      })
      .mockResolvedValueOnce("a0SNEW");
    const el = createElement("c-kem-session-modal", { is: KemSessionModal });
    el.offeringId = "0P01";
    el.offeringName = "Abacus – Sat";
    const closed = jest.fn();
    el.addEventListener("close", closed);
    document.body.appendChild(el);
    await flush();
    const root = el.shadowRoot;
    const day = root.querySelector("lightning-input.day");
    day.value = "2026-10-17";
    day.dispatchEvent(new CustomEvent("change"));
    const time = root.querySelector("lightning-input.time");
    time.value = "11:00:00.000";
    time.dispatchEvent(new CustomEvent("change"));
    await flush();
    const add = () =>
      [...root.querySelectorAll("lightning-button")].find(
        (b) => b.label === "Add session"
      );
    add().click();
    await flush();
    await flush();
    expect(root.querySelector('[role="alert"]').textContent).toContain(
      "already booked"
    );
    add().click();
    await flush();
    const call = addSession.mock.calls[1][0];
    expect(call).toMatchObject({
      offeringId: "0P01",
      sessionType: "Make-up",
      roomId: null
    });
    const start = new Date(call.startAt);
    expect(start.getHours()).toBe(11);
    expect((new Date(call.endAt) - start) / 60000).toBe(60);
    expect(closed.mock.calls[0][0].detail).toBe("a0SNEW");
  });
});
