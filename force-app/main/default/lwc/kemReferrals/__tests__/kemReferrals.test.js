import { createElement } from "lwc";
import KemReferrals from "c/kemReferrals";
import LightningPrompt from "lightning/prompt";
import getDesk from "@salesforce/apex/ReferralController.getDesk";
import grantReward from "@salesforce/apex/ReferralController.grantReward";
import markNotEligible from "@salesforce/apex/ReferralController.markNotEligible";
import inviteAlumni from "@salesforce/apex/ReferralController.inviteAlumni";

jest.mock(
  "@salesforce/apex/ReferralController.getDesk",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ReferralController.grantReward",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ReferralController.markNotEligible",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ReferralController.inviteAlumni",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = async () => {
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => process.nextTick(resolve));
  }
};

const DESK = {
  canReward: true,
  rewardMode: "Manual",
  rewardAmount: 500,
  conversionRate: 50,
  alumniTotal: 2,
  counts: { Enquired: 1, Enrolled: 1, Rewarded: 0, "Not Eligible": 0 },
  referrals: [
    {
      referralId: "f1",
      referred: "Nikhil",
      referrer: "Priya",
      status: "Enrolled"
    },
    {
      referralId: "f2",
      referred: "Ravi",
      referrer: "Priya",
      status: "Enquired"
    }
  ],
  topReferrers: [
    {
      accountId: "a1",
      name: "Priya",
      code: "REF-7Q2X",
      referrals: 2,
      enrolled: 1
    }
  ],
  alumni: [
    { accountId: "o1", name: "Olga", since: "2026-10-06", contactOk: true },
    { accountId: "o2", name: "Omar", contactOk: false }
  ]
};

async function mount() {
  const el = createElement("c-kem-referrals", { is: KemReferrals });
  document.body.appendChild(el);
  await flush();
  return el;
}

function buttons(el, label) {
  return [...el.shadowRoot.querySelectorAll("lightning-button")].filter(
    (b) => b.label === label
  );
}

describe("c-kem-referrals", () => {
  beforeEach(() => {
    getDesk.mockResolvedValue(DESK);
  });
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows counts, the reward rule, referrals, top referrers and alumni", async () => {
    const el = await mount();
    expect(getDesk).toHaveBeenCalledWith({ branchId: null });
    expect(el.shadowRoot.querySelectorAll(".tile")).toHaveLength(5);
    expect(el.shadowRoot.textContent).toContain("50%");
    expect(el.shadowRoot.textContent).toContain("granted by finance below");
    expect(buttons(el, "Grant reward")).toHaveLength(1);
    expect(buttons(el, "Not eligible")).toHaveLength(2);
    expect(el.shadowRoot.textContent).toContain("1 joined of 2 referred");
    expect(
      el.shadowRoot.querySelector("lightning-checkbox-group").options
    ).toHaveLength(1);
    expect(el.shadowRoot.textContent).toContain(
      "1 other alumni asked not to be contacted"
    );
  });

  it("grants a reward and declines a referral", async () => {
    grantReward.mockResolvedValue("cn1");
    markNotEligible.mockResolvedValue();
    LightningPrompt.open = jest
      .fn()
      .mockResolvedValue("Sibling discount instead");
    const el = await mount();
    buttons(el, "Grant reward")[0].click();
    await flush();
    expect(grantReward).toHaveBeenCalledWith({ referralId: "f1" });
    buttons(el, "Not eligible")[1].click();
    await flush();
    expect(markNotEligible).toHaveBeenCalledWith({
      referralId: "f2",
      note: "Sibling discount instead"
    });
  });

  it("invites selected alumni", async () => {
    inviteAlumni.mockResolvedValue(1);
    const el = await mount();
    el.shadowRoot
      .querySelector("lightning-checkbox-group")
      .dispatchEvent(new CustomEvent("change", { detail: { value: ["o1"] } }));
    await flush();
    buttons(el, "Invite selected")[0].click();
    await flush();
    const text = el.shadowRoot.querySelector("lightning-textarea");
    text.value = "New robotics classes";
    text.dispatchEvent(new CustomEvent("change"));
    buttons(el, "Send invitations")[0].click();
    await flush();
    expect(inviteAlumni).toHaveBeenCalledWith({
      accountIds: ["o1"],
      message: "New robotics classes"
    });
  });

  it("explains when rewards are off and hides without access", async () => {
    getDesk.mockResolvedValue({
      ...DESK,
      rewardMode: "Off",
      canReward: false,
      referrals: [],
      alumni: []
    });
    const el = await mount();
    expect(el.shadowRoot.textContent).toContain("switched off");
    expect(el.shadowRoot.textContent).toContain("No referrals yet");
    document.body.removeChild(el);
    getDesk.mockRejectedValue({
      body: { message: "You do not have access to the Apex class" }
    });
    const hidden = await mount();
    expect(hidden.shadowRoot.querySelector("article")).toBeNull();
  });
});
