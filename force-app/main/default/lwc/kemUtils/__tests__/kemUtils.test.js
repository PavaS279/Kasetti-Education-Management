import {
  reduceErrors,
  initials,
  toneFor,
  relativeTime,
  followUpClass,
  formatDateTime
} from "c/kemUtils";

describe("c-kem-utils", () => {
  it("reduces Apex, page, field, and plain errors", () => {
    expect(reduceErrors({ body: { message: "Apex failed" } })).toEqual([
      "Apex failed"
    ]);
    expect(
      reduceErrors([{ body: [{ message: "A" }, { message: "B" }] }])
    ).toEqual(["A", "B"]);
    expect(
      reduceErrors({ body: { pageErrors: [{ message: "Page" }] } })
    ).toEqual(["Page"]);
    expect(
      reduceErrors({
        body: { fieldErrors: { Name: [{ message: "Required" }] } }
      })
    ).toEqual(["Required"]);
    expect(reduceErrors(new Error("Plain"))).toEqual(["Plain"]);
    expect(reduceErrors([null, undefined])).toEqual([]);
  });

  it("builds initials", () => {
    expect(initials("Asha Rao")).toBe("AR");
    expect(initials("Meera Devi Iyer")).toBe("MI");
    expect(initials("Kiran")).toBe("K");
    expect(initials("")).toBe("?");
  });

  it("picks a stable tone", () => {
    expect(toneFor("Asha Rao")).toBe(toneFor("Asha Rao"));
    expect(toneFor("Asha Rao")).toMatch(/^tone-[1-6]$/);
  });

  it("formats relative time in both directions", () => {
    const now = Date.now();
    expect(relativeTime(new Date(now + 30 * 60000).toISOString())).toMatch(
      /^in \d+m$/
    );
    expect(relativeTime(new Date(now - 5 * 3600000).toISOString())).toBe(
      "5h ago"
    );
    expect(relativeTime(new Date(now + 3 * 86400000).toISOString())).toBe(
      "in 3d"
    );
    expect(relativeTime(null)).toBe("");
  });

  it("maps follow-up statuses to badge classes", () => {
    expect(followUpClass("Overdue")).toContain("danger");
    expect(followUpClass("Due Today")).toContain("warning");
    expect(followUpClass("Scheduled")).toContain("success");
    expect(followUpClass("Not Scheduled")).toBe("kem-badge");
  });

  it("formats date time and handles blanks", () => {
    expect(formatDateTime(null)).toBe("");
    expect(formatDateTime("2026-10-02T10:00:00.000Z")).not.toBe("");
  });
});
