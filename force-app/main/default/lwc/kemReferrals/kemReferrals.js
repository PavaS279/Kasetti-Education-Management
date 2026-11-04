import { LightningElement, api } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import LOCALE from "@salesforce/i18n/locale";
import LightningPrompt from "lightning/prompt";
import getDesk from "@salesforce/apex/ReferralController.getDesk";
import grantReward from "@salesforce/apex/ReferralController.grantReward";
import markNotEligible from "@salesforce/apex/ReferralController.markNotEligible";
import inviteAlumni from "@salesforce/apex/ReferralController.inviteAlumni";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const BADGE = {
  Enquired: "kem-badge kem-badge_info",
  Enrolled: "kem-badge kem-badge_warning",
  Rewarded: "kem-badge kem-badge_success",
  "Not Eligible": "kem-badge"
};

/** Referrals and alumni: referral pipeline, rewards, top referrers and alumni invitations. */
export default class KemReferrals extends LightningElement {
  @api recordId;
  desk;
  errorMessage;
  hidden = false;
  isBusy = false;
  selectedAlumni = [];
  showInvite = false;
  inviteText = "";

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.desk = await getDesk({ branchId: this.recordId || null });
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  money(value) {
    return new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency: CURRENCY,
      maximumFractionDigits: 0
    }).format(value || 0);
  }

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.desk && !this.errorMessage;
  }
  get tiles() {
    const c = this.desk?.counts || {};
    const rate = this.desk?.conversionRate;
    return [
      { key: "enq", label: "Referred enquiries", value: c.Enquired || 0 },
      { key: "enr", label: "Enrolled, reward due", value: c.Enrolled || 0 },
      { key: "rew", label: "Rewarded", value: c.Rewarded || 0 },
      {
        key: "conv",
        label: "Referrals that enrolled",
        value: rate === null || rate === undefined ? "—" : `${rate}%`
      },
      { key: "alumni", label: "Alumni", value: this.desk?.alumniTotal || 0 }
    ];
  }
  get rewardNote() {
    const d = this.desk;
    if (!d) {
      return "";
    }
    if (d.rewardMode === "Off") {
      return "Referral rewards are switched off.";
    }
    const how =
      d.rewardMode === "Auto"
        ? "granted automatically when the referred learner enrols"
        : "granted by finance below";
    return `Reward: ${this.money(d.rewardAmount)} credit to the referrer, ${how}.`;
  }
  get referrals() {
    const canReward = this.desk?.canReward === true;
    return (this.desk?.referrals || []).map((r) => ({
      ...r,
      badge: BADGE[r.status] || "kem-badge",
      reward: r.reward ? `${this.money(r.reward)} (${r.creditNote})` : "",
      canReward: canReward && r.status === "Enrolled",
      canDecline:
        canReward && (r.status === "Enrolled" || r.status === "Enquired")
    }));
  }
  get hasReferrals() {
    return this.referrals.length > 0;
  }
  get topReferrers() {
    return (this.desk?.topReferrers || []).map((r, i) => ({
      ...r,
      rank: i + 1,
      line: `${r.enrolled} joined of ${r.referrals} referred`
    }));
  }
  get hasTopReferrers() {
    return this.topReferrers.length > 0;
  }
  get alumniOptions() {
    return (this.desk?.alumni || [])
      .filter((a) => a.contactOk)
      .map((a) => ({
        label: `${a.name}${a.since ? ` (since ${a.since})` : ""}`,
        value: a.accountId
      }));
  }
  get noContactCount() {
    return (this.desk?.alumni || []).filter((a) => !a.contactOk).length;
  }
  get hasAlumni() {
    return (this.desk?.alumni || []).length > 0;
  }
  get inviteDisabled() {
    return this.isBusy || this.selectedAlumni.length === 0;
  }

  async handleReward(event) {
    const referralId = event.currentTarget.dataset.id;
    await this.run(async () => {
      await grantReward({ referralId });
      toast(
        this,
        "Reward granted",
        "A credit note was issued to the referrer and they were told.",
        "success"
      );
    });
  }

  async handleDecline(event) {
    const referralId = event.currentTarget.dataset.id;
    const note = await LightningPrompt.open({
      label: "Not eligible for a reward",
      message: "Why does this referral not qualify?",
      variant: "header"
    });
    if (note === null || note === undefined) {
      return;
    }
    await this.run(async () => {
      await markNotEligible({ referralId, note });
      toast(this, "Referral marked not eligible", "", "success");
    });
  }

  handleAlumni(event) {
    this.selectedAlumni = event.detail.value;
  }

  toggleInvite() {
    this.showInvite = !this.showInvite;
  }

  handleInviteText(event) {
    this.inviteText = event.target.value || "";
  }

  async handleInvite() {
    await this.run(async () => {
      const sent = await inviteAlumni({
        accountIds: this.selectedAlumni,
        message: this.inviteText
      });
      toast(
        this,
        "Invitations sent",
        `${sent} message(s), each with the alumnus's referral code.`,
        "success"
      );
      this.selectedAlumni = [];
      this.showInvite = false;
      this.inviteText = "";
    });
  }

  async run(action) {
    this.isBusy = true;
    try {
      await action();
      await this.load();
    } catch (error) {
      toastError(this, error);
    } finally {
      this.isBusy = false;
    }
  }
}
