import { createElement } from "lwc";
import KemTimetable from "c/kemTimetable";
import getWeek from "@salesforce/apex/TimetableController.getWeek";
import getFilters from "@salesforce/apex/TimetableController.getFilters";

jest.mock(
  "@salesforce/apex/TimetableController.getWeek",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimetableController.getFilters",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimetableController.previewMove",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimetableController.reschedule",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TimetableController.cancelSession",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

function mondayAt(hours, minutes) {
  const d = new Date();
  const offset = (d.getDay() + 6) % 7;
  return new Date(
    d.getFullYear(),
    d.getMonth(),
    d.getDate() - offset,
    hours,
    minutes
  );
}

describe("c-kem-timetable", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("positions sessions by time and opens the detail drawer", async () => {
    const element = createElement("c-kem-timetable", { is: KemTimetable });
    document.body.appendChild(element);
    getFilters.emit({
      branches: [],
      teachers: [],
      rooms: [],
      currentUserId: "005000000000001"
    });
    const start = mondayAt(9, 0);
    const end = mondayAt(10, 30);
    getWeek.emit([
      {
        id: "a0S000000000001",
        name: "S1",
        classId: "0kF000000000001",
        className: "Maths Sat AM",
        startAt: start.toISOString(),
        endAt: end.toISOString(),
        status: "Scheduled",
        sessionType: "Class",
        roomName: "Room 101"
      },
      {
        id: "a0S000000000002",
        name: "S2",
        classId: "0kF000000000002",
        className: "Art",
        startAt: mondayAt(13, 0).toISOString(),
        endAt: mondayAt(14, 0).toISOString(),
        status: "Cancelled",
        sessionType: "Class"
      }
    ]);
    await Promise.resolve();
    const sessions = element.shadowRoot.querySelectorAll("article.session");
    expect(sessions).toHaveLength(2);
    // 09:00 is 2 hours after the 07:00 grid start at 56px per hour.
    expect(sessions[0].getAttribute("style")).toContain("top: 112px");
    expect(sessions[0].getAttribute("style")).toContain("height: 82px");
    expect(sessions[1].className).toContain("session_cancelled");
    expect(sessions[1].getAttribute("draggable")).toBe("false");

    sessions[0].click();
    await Promise.resolve();
    const drawer = element.shadowRoot.querySelector("aside.drawer");
    expect(drawer.textContent).toContain("Maths Sat AM");
    expect(drawer.textContent).toContain("Room 101");
  });
});
