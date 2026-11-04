import { createElement } from "lwc";
import KemPortalCollege from "c/kemPortalCollege";

const SUMMARY = {
  campus: "Yelahanka Campus",
  programme: "BE",
  branch: "CSE",
  rollNumber: "KT26YBCS001",
  status: "Enrolled",
  academicYear: "2026-27",
  yearOfStudy: 1,
  section: "YLK BE-CSE Y1 A",
  feesDue: 0,
  openBacklogs: 0,
  today: [
    {
      subject: "Engineering Mathematics I",
      startsAt: "2026-10-14T03:30:00.000Z",
      endsAt: "2026-10-14T04:30:00.000Z",
      room: "B-201",
      faculty: "Tara Teacher",
      status: "Scheduled"
    }
  ],
  subjects: [
    {
      name: "Engineering Mathematics I",
      term: 1,
      attempt: 1,
      attendancePercent: 95,
      published: true,
      internalMarks: 40,
      examMarks: 80,
      total: 120,
      max: 150,
      result: "Pass"
    },
    { name: "Physics", term: 1, attempt: 1, published: false }
  ],
  terms: [{ term: 1, outcome: "Pass", percentage: 80, backlogs: 0 }]
};

function mount(summary) {
  const element = createElement("c-kem-portal-college", {
    is: KemPortalCollege
  });
  element.summary = summary;
  document.body.appendChild(element);
  return element;
}

describe("c-kem-portal-college", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("shows roll number, today's period, published marks and term results", () => {
    const element = mount(SUMMARY);
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Roll number KT26YBCS001");
    expect(text).toContain("B-201");
    expect(text).toContain("120 / 150");
    expect(text).toContain("95%");
    expect(text).toContain("Term 1: Pass");
  });

  it("hides marks that are not final yet", () => {
    const element = mount(SUMMARY);
    const rows = element.shadowRoot.querySelectorAll("tbody tr");
    expect(rows[1].textContent).toContain("Result awaited");
    expect(rows[1].textContent).not.toContain("/");
  });

  it("explains when the roll number and classes are not there yet", () => {
    const element = mount({
      ...SUMMARY,
      rollNumber: null,
      status: "Provisional",
      feesDue: 155000,
      paymentDueBy: "2026-10-20",
      today: [],
      subjects: [],
      terms: []
    });
    const text = element.shadowRoot.textContent;
    expect(text).toContain("Roll number after the fee is received");
    expect(text).toContain("Pay by 2026-10-20");
    expect(text).toContain("No classes today.");
  });
});
