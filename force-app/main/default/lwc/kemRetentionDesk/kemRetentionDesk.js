import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getDesk from "@salesforce/apex/RetentionController.getDesk";
import recordFollowUp from "@salesforce/apex/RetentionController.recordFollowUp";
import invite from "@salesforce/apex/RetentionController.invite";
import recalculate from "@salesforce/apex/RetentionController.recalculate";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const LEVELS = [
  { label: "High and medium", value: "All" },
  { label: "High", value: "High" },
  { label: "Medium", value: "Medium" }
];
const OUTCOMES = [
  { label: "Contacted", value: "Contacted" },
  { label: "Retained", value: "Retained" },
  { label: "Leaving", value: "Leaving" },
  { label: "Follow-up needed", value: "Follow-up Needed" }
];

/** Retention desk: at-risk learners and re-enrolment invitations. */
export default class KemRetentionDesk extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  data;
  errorMessage;
  hidden = false;
  tab = "risk";
  level = "All";
  levelOptions = LEVELS;
  outcomeOptions = OUTCOMES;
  editingId;
  outcome = "Contacted";
  note = "";
  selected = new Set();
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getDesk({
        branchId: this.recordId || null,
        level: this.level
      });
      this.errorMessage = undefined;
      this.selected = new Set();
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get isRisk() {
    return this.tab === "risk";
  }
  get isInvite() {
    return this.tab === "invite";
  }
  get riskTabClass() {
    return `tab${this.isRisk ? " tab_active" : ""}`;
  }
  get inviteTabClass() {
    return `tab${this.isInvite ? " tab_active" : ""}`;
  }
  get counts() {
    const d = this.data;
    return [
      {
        key: "high",
        label: "High risk",
        value: d.high,
        className: "count count_high"
      },
      {
        key: "medium",
        label: "Medium risk",
        value: d.medium,
        className: "count count_medium"
      },
      {
        key: "follow",
        label: "Follow-up needed",
        value: d.followUpNeeded,
        className: "count"
      },
      {
        key: "retained",
        label: "Retained",
        value: d.retained,
        className: "count"
      }
    ];
  }
  get assessedLabel() {
    return this.data.lastAssessed
      ? `Scores from ${new Intl.DateTimeFormat(undefined, {
          day: "numeric",
          month: "short",
          hour: "numeric",
          minute: "2-digit"
        }).format(new Date(this.data.lastAssessed))}`
      : "Not scored yet";
  }
  get rows() {
    return this.data.atRisk.map((r) => ({
      ...r,
      badgeClass: `kem-badge ${r.level === "High" ? "kem-badge_danger" : "kem-badge_warning"}`,
      statusLabel: r.status || "No follow-up yet",
      editing: r.enrolmentId === this.editingId
    }));
  }
  get hasRows() {
    return this.data.atRisk.length > 0;
  }
  get candidates() {
    return this.data.candidates.map((c) => ({
      ...c,
      checked: this.selected.has(c.enrolmentId),
      invitedLabel: c.invitedOn
        ? `Invited ${new Date(c.invitedOn).toLocaleDateString()}`
        : "Not invited"
    }));
  }
  get hasCandidates() {
    return this.data.candidates.length > 0;
  }
  get inviteLabel() {
    return `Send invitations (${this.selected.size})`;
  }
  get cannotInvite() {
    return this.isBusy || this.selected.size === 0;
  }
  get cannotSave() {
    return this.isBusy || (this.outcome !== "Retained" && !this.note.trim());
  }

  handleTab(event) {
    this.tab = event.currentTarget.dataset.tab;
  }
  handleLevel(event) {
    this.level = event.detail.value;
    this.load();
  }
  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }
  handleEdit(event) {
    this.editingId = event.currentTarget.dataset.id;
    this.outcome = "Contacted";
    this.note = "";
  }
  handleCancelEdit() {
    this.editingId = undefined;
  }
  handleOutcome(event) {
    this.outcome = event.detail.value;
  }
  handleNote(event) {
    this.note = event.target.value || "";
  }

  async handleSave() {
    this.isBusy = true;
    try {
      await recordFollowUp({
        enrolmentId: this.editingId,
        status: this.outcome,
        note: this.note.trim()
      });
      toast(this, "Follow-up saved", `Outcome: ${this.outcome}.`);
      this.editingId = undefined;
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not save the follow-up");
    } finally {
      this.isBusy = false;
    }
  }

  handleSelect(event) {
    const id = event.target.dataset.id;
    const next = new Set(this.selected);
    if (event.target.checked) {
      next.add(id);
    } else {
      next.delete(id);
    }
    this.selected = next;
  }

  async handleInvite() {
    this.isBusy = true;
    try {
      const created = await invite({ enrolmentIds: [...this.selected] });
      toast(
        this,
        "Invitations sent",
        `${created} message(s) created for the families.`
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not send invitations");
    } finally {
      this.isBusy = false;
    }
  }

  async handleRecalculate() {
    this.isBusy = true;
    try {
      await recalculate();
      toast(
        this,
        "Recalculating",
        "Risk scores are being recalculated in the background."
      );
    } catch (error) {
      toastError(this, error, "Could not start the recalculation");
    } finally {
      this.isBusy = false;
    }
  }

  handleRefresh() {
    this.load();
  }
}
