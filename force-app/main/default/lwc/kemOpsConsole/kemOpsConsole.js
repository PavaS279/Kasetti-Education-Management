import { LightningElement } from "lwc";
import getConsole from "@salesforce/apex/OpsController.getConsole";
import ensureSchedules from "@salesforce/apex/OpsController.ensureSchedules";
import runNow from "@salesforce/apex/OpsController.runNow";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const HEALTH = {
  healthy: {
    label: "All systems normal",
    icon: "utility:success",
    className: "health health_ok"
  },
  attention: {
    label: "Needs attention",
    icon: "utility:warning",
    className: "health health_warn"
  },
  failing: {
    label: "Action required",
    icon: "utility:error",
    className: "health health_bad"
  }
};

const when = (value) =>
  value
    ? new Intl.DateTimeFormat(undefined, {
        day: "numeric",
        month: "short",
        hour: "numeric",
        minute: "2-digit"
      }).format(new Date(value))
    : "—";

/** Operations console: scheduled jobs, background runs, errors and exception queues. */
export default class KemOpsConsole extends LightningElement {
  data;
  errorMessage;
  hidden = false;
  isBusy = false;
  showErrors = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getConsole();
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      // Not an administrator: the console simply does not show.
      this.hidden = message.includes("administrators");
      this.errorMessage = message;
    }
  }

  get visible() {
    return !this.hidden;
  }
  get health() {
    return HEALTH[this.data.health] || HEALTH.attention;
  }
  get issues() {
    return this.data.issues
      .slice(0, 6)
      .map((text, i) => ({ key: String(i), text }));
  }
  get hasIssues() {
    return this.data.issues.length > 0;
  }
  get queues() {
    return this.data.queues.map((q) => ({
      ...q,
      className: `tile${q.count > 0 ? ` tile_${q.severity}` : ""}`
    }));
  }
  get schedules() {
    return this.data.schedules.map((s) => ({
      ...s,
      next: when(s.nextRun),
      last: when(s.lastRun),
      stateClass: s.missing
        ? "kem-badge kem-badge_danger"
        : s.state === "WAITING" ||
            s.state === "EXECUTING" ||
            s.state === "ACQUIRED"
          ? "kem-badge kem-badge_success"
          : "kem-badge kem-badge_warning",
      runLabel: `Run ${s.name} now`
    }));
  }
  get anyMissing() {
    return this.data.schedules.some((s) => s.missing);
  }
  get runs() {
    return this.data.runs.slice(0, 10).map((r) => ({
      ...r,
      when: when(r.createdDate),
      progress: r.totalItems ? `${r.itemsProcessed}/${r.totalItems}` : "",
      className: `run${r.problem ? " run_bad" : ""}`
    }));
  }
  get noRuns() {
    return this.data.runs.length === 0;
  }
  get errors() {
    return this.data.recentErrors.map((e) => ({
      ...e,
      when: when(e.CreatedDate),
      message: (e.Message__c || "").slice(0, 200)
    }));
  }
  get errorToggleLabel() {
    return this.showErrors
      ? "Hide errors"
      : `Show errors (${this.data.recentErrors.length})`;
  }
  get hasErrors() {
    return this.data.recentErrors.length > 0;
  }
  get generated() {
    return when(this.data.generatedAt);
  }

  handleRefresh() {
    this.load();
  }

  handleToggleErrors() {
    this.showErrors = !this.showErrors;
  }

  async handleEnsure() {
    this.isBusy = true;
    try {
      const added = await ensureSchedules();
      toast(this, "Schedules checked", `${added} job(s) scheduled.`);
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not schedule jobs");
    } finally {
      this.isBusy = false;
    }
  }

  async handleRun(event) {
    const jobName = event.currentTarget.dataset.name;
    this.isBusy = true;
    try {
      await runNow({ jobName });
      toast(this, "Job started", `${jobName} is running in the background.`);
      await this.load();
    } catch (error) {
      toastError(this, error, "Could not start the job");
    } finally {
      this.isBusy = false;
    }
  }
}
