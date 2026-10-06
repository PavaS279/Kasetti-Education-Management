import { LightningElement } from "lwc";
import getConsole from "@salesforce/apex/AiController.getConsole";
import runEvaluation from "@salesforce/apex/AiController.runEvaluation";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const PERIODS = [
  { label: "Last 7 days", value: "7" },
  { label: "Last 30 days", value: "30" },
  { label: "Last 90 days", value: "90" }
];

function percent(value) {
  return value === null || value === undefined ? "—" : `${value}%`;
}

/** AI console: measured benefit, quality and controls of the Einstein assistants. */
export default class KemAiConsole extends LightningElement {
  data;
  errorMessage;
  hidden = false;
  days = "30";
  periodOptions = PERIODS;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getConsole({ days: Number(this.days) });
      this.hidden = !this.data.canUse && !this.data.isAdmin;
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get statusLabel() {
    return this.data.enabled ? "AI on" : "AI switched off";
  }
  get statusClass() {
    return `kem-badge ${this.data.enabled ? "kem-badge_success" : "kem-badge_danger"}`;
  }
  get modelLabel() {
    return (this.data.model || "").replace("sfdc_ai__Default", "");
  }
  get tiles() {
    const t = this.data.totals;
    return [
      { key: "calls", label: "AI requests", value: String(t.calls) },
      { key: "users", label: "Staff using AI", value: String(this.data.users) },
      {
        key: "agent",
        label: "Agentforce actions",
        value: String(this.data.agentCalls || 0)
      },
      {
        key: "accept",
        label: "Used (as is or edited)",
        value: percent(t.acceptanceRate)
      },
      {
        key: "minutes",
        label: "Minutes saved (est.)",
        value: String(t.minutesSaved)
      },
      {
        key: "latency",
        label: "Average response",
        value: t.averageLatencyMs
          ? `${(t.averageLatencyMs / 1000).toFixed(1)} s`
          : "—"
      },
      {
        key: "failed",
        label: "Failed requests",
        value: String(t.failed),
        warn: t.failed > 0
      }
    ].map((x) => ({ ...x, className: `tile${x.warn ? " tile_warn" : ""}` }));
  }
  get features() {
    return this.data.features.map((f) => ({
      ...f,
      acceptance: percent(f.acceptanceRate),
      edit: percent(f.averageEdit),
      rating: f.averageRating ? `${f.averageRating} / 5` : "—",
      pending: f.calls - f.failed - f.reviewed
    }));
  }
  get hasFeatures() {
    return this.data.features.length > 0;
  }
  get evaluation() {
    const e = this.data.evaluation;
    return e
      ? {
          ...e,
          label: `${e.passed} of ${e.cases} cases passed · average score ${e.averageScore}% · ${(e.averageLatencyMs / 1000).toFixed(1)} s`,
          className: `kem-badge ${e.passed === e.cases ? "kem-badge_success" : "kem-badge_warning"}`
        }
      : null;
  }

  handlePeriod(event) {
    this.days = event.detail.value;
    this.load();
  }

  async handleEvaluate() {
    this.isBusy = true;
    try {
      const run = await runEvaluation();
      toast(
        this,
        "Evaluation finished",
        `${run.passed} of ${run.cases} cases passed.`
      );
      await this.load();
    } catch (error) {
      toastError(this, error, "Evaluation failed");
    } finally {
      this.isBusy = false;
    }
  }
}
