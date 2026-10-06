import { createElement } from "lwc";
import KemAiReportComments from "c/kemAiReportComments";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import classLearners from "@salesforce/apex/AiController.classLearners";
import reportComment from "@salesforce/apex/AiController.reportComment";
import useReportComment from "@salesforce/apex/AiController.useReportComment";

jest.mock(
  "@salesforce/apex/AiController.isAvailable",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/AiController.classLearners",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.reportComment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.useReportComment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AiController.review",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
const flush = () => new Promise((resolve) => process.nextTick(resolve));
const RESULT = {
  ok: true,
  text: "Dear Rohit,\nThank you.",
  interactionId: "a0X1",
  model: "sfdc_ai__DefaultGPT4Omni",
  latencyMs: 800,
  feature: "X"
};

describe("c-kem-ai-report-comments", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("drafts and saves a learner's comment", async () => {
    classLearners.mockResolvedValue([
      {
        enrolmentId: "0x6A",
        learner: "Ananya Sharma",
        grade: "A+",
        comment: "Excellent term."
      },
      { enrolmentId: "0x6B", learner: "Arjun Sharma", grade: "C" }
    ]);
    reportComment.mockResolvedValue(RESULT);
    useReportComment.mockResolvedValue();
    const el = createElement("c-kem-ai-report-comments", {
      is: KemAiReportComments
    });
    el.recordId = "0Pq1";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    const rows = el.shadowRoot.querySelectorAll(".row");
    expect(rows).toHaveLength(2);
    expect(rows[0].querySelector(".comment").textContent).toBe(
      "Excellent term."
    );
    rows[1].querySelector("lightning-button").click();
    await flush();
    expect(reportComment).toHaveBeenCalledWith({ enrolmentId: "0x6B" });
    el.shadowRoot.querySelector("c-kem-ai-draft").dispatchEvent(
      new CustomEvent("use", {
        detail: { text: "Arjun is improving.", interactionId: "a0X1" }
      })
    );
    await flush();
    await flush();
    expect(useReportComment).toHaveBeenCalledWith({
      enrolmentId: "0x6B",
      comment: "Arjun is improving.",
      interactionId: "a0X1"
    });
    expect(classLearners).toHaveBeenCalledTimes(2);
  });

  it("shows an empty class and errors", async () => {
    classLearners.mockResolvedValue([]);
    const el = createElement("c-kem-ai-report-comments", {
      is: KemAiReportComments
    });
    el.recordId = "0Pq1";
    document.body.appendChild(el);
    isAvailable.emit(true);
    await flush();
    expect(el.shadowRoot.textContent).toContain("No learners");
  });
});
