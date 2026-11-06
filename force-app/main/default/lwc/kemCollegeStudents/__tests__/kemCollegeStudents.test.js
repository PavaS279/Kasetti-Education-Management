import { createElement } from "lwc";
import KemCollegeStudents from "c/kemCollegeStudents";
import getStudents from "@salesforce/apex/CollegeStudentsController.getStudents";
import setUsn from "@salesforce/apex/CollegeStudentsController.setUsn";

jest.mock(
  "@salesforce/apex/CollegeStudentsController.getStudents",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/CollegeStudentsController.setUsn",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () => new Promise((resolve) => process.nextTick(resolve));

const DATA = {
  summary: { enrolled: 1, feePending: 1, withoutSection: 0, feesDue: 155000 },
  campuses: [
    { label: "Yelahanka Campus", value: "a0M1" },
    { label: "Rajajinagar Campus", value: "a0M2" }
  ],
  students: [
    {
      enrolmentId: "a1E1",
      studentId: "0011",
      student: "Spoorti B",
      rollNumber: "KT26YBCS001",
      status: "Enrolled",
      campusId: "a0M1",
      campus: "Yelahanka Campus",
      branch: "BE Computer Science and Engineering",
      yearOfStudy: 1,
      academicYear: "2026-27",
      section: "YLK · BE-CSE · 2026-27 · Y1 · A",
      feesDue: 0,
      hasEmail: true,
      hasPortal: true
    },
    {
      enrolmentId: "a1E2",
      studentId: "0012",
      student: "Kiran Patil",
      status: "Provisional",
      campusId: "a0M2",
      campus: "Rajajinagar Campus",
      branch: "BE Computer Science and Engineering",
      yearOfStudy: 2,
      academicYear: "2026-27",
      feesDue: 155000,
      paymentDueBy: "2026-11-11",
      hasEmail: false,
      hasPortal: false
    }
  ]
};

function mount() {
  const element = createElement("c-kem-college-students", {
    is: KemCollegeStudents
  });
  document.body.appendChild(element);
  return element;
}

const names = (element) =>
  [...element.shadowRoot.querySelectorAll("li.row a.strong")].map(
    (a) => a.textContent
  );

describe("c-kem-college-students", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists every student with roll number, section, fees and portal state", async () => {
    getStudents.mockResolvedValue(DATA);
    const element = mount();
    await flush();
    expect(getStudents).toHaveBeenCalledWith({ scope: "current" });
    expect(names(element)).toEqual(["Spoorti B", "Kiran Patil"]);
    const text = element.shadowRoot.textContent;
    expect(text).toContain("KT26YBCS001");
    expect(text).toContain("YLK · BE-CSE · 2026-27 · Y1 · A");
    expect(text).toContain("Fee pending");
    expect(text).toContain("pay by");
    expect(text).toContain("Portal: active");
    expect(text).toContain("Portal: needs an email");
    expect(text).toContain("2 students");
  });

  it("filters by campus and search", async () => {
    getStudents.mockResolvedValue(DATA);
    const element = mount();
    await flush();
    const campus = [
      ...element.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.label === "Campus");
    campus.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a0M2" } })
    );
    await flush();
    expect(names(element)).toEqual(["Kiran Patil"]);

    campus.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
    const search = element.shadowRoot.querySelector("lightning-input.search");
    search.value = "kt26";
    search.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(names(element)).toEqual(["Spoorti B"]);
  });

  it("enters a USN for an enrolled student", async () => {
    getStudents.mockResolvedValue({ ...DATA, canSetUsn: true });
    setUsn.mockResolvedValue();
    const element = mount();
    await flush();
    expect(element.shadowRoot.textContent).toContain("USN awaited");
    const enter = [
      ...element.shadowRoot.querySelectorAll("lightning-button")
    ].find((b) => b.label === "Enter USN");
    enter.click();
    await flush();
    const input = element.shadowRoot.querySelector("lightning-input.usn");
    input.value = "1kt26cs001";
    input.dispatchEvent(new CustomEvent("change"));
    [...element.shadowRoot.querySelectorAll("lightning-button-icon")]
      .find((b) => b.alternativeText === "Save USN")
      .click();
    await flush();
    expect(setUsn).toHaveBeenCalledWith({
      enrolmentId: "a1E1",
      usn: "1KT26CS001",
      reason: ""
    });
    expect(element.shadowRoot.textContent).toContain("1KT26CS001");
  });

  it("reloads with past students", async () => {
    getStudents.mockResolvedValue(DATA);
    const element = mount();
    await flush();
    const show = [
      ...element.shadowRoot.querySelectorAll("lightning-combobox")
    ].find((c) => c.label === "Show");
    show.dispatchEvent(new CustomEvent("change", { detail: { value: "all" } }));
    await flush();
    expect(getStudents).toHaveBeenLastCalledWith({ scope: "all" });
  });

  it("shows the server message when access is refused", async () => {
    getStudents.mockRejectedValue({
      body: {
        message:
          "Only the college admission desk and the Dean can see the student list."
      }
    });
    const element = mount();
    await flush();
    expect(element.shadowRoot.textContent).toContain(
      "Only the college admission desk and the Dean"
    );
  });
});
