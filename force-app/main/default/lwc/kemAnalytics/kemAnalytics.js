import { LightningElement, api } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import LOCALE from "@salesforce/i18n/locale";
import getDashboard from "@salesforce/apex/AnalyticsController.getDashboard";
import getBranches from "@salesforce/apex/AnalyticsController.getBranches";
import { reduceErrors } from "c/kemUtils";

// Chart geometry (SVG user units; the SVG scales to its container).
const W = 640;
const H = 220;
const PAD = { top: 12, right: 8, bottom: 28, left: 52 };
const PLOT_W = W - PAD.left - PAD.right;
const PLOT_H = H - PAD.top - PAD.bottom;
const GAP = 2; // surface gap between adjacent bars
const RADIUS = 4; // rounded data-end

const PERIODS = [
  { label: "6 months", value: "6" },
  { label: "12 months", value: "12" },
  { label: "24 months", value: "24" }
];

function niceMax(value) {
  if (!value || value <= 0) {
    return 1;
  }
  const magnitude = 10 ** Math.floor(Math.log10(value));
  const steps = [1, 2, 2.5, 5, 10];
  for (const step of steps) {
    if (step * magnitude >= value) {
      return step * magnitude;
    }
  }
  return 10 * magnitude;
}

/** Bar path with a rounded top, anchored to the baseline. */
function barPath(x, y, width, height) {
  if (height <= 0) {
    return "";
  }
  const r = Math.min(RADIUS, width / 2, height);
  const bottom = y + height;
  return (
    `M${x},${bottom} L${x},${y + r} Q${x},${y} ${x + r},${y} ` +
    `L${x + width - r},${y} Q${x + width},${y} ${x + width},${y + r} ` +
    `L${x + width},${bottom} Z`
  );
}

/** Analytics dashboard: trends, cohorts, ageing and course performance. */
export default class KemAnalytics extends LightningElement {
  @api recordId;
  data;
  errorMessage;
  hidden = false;
  branchId = "";
  months = "12";
  periodOptions = PERIODS;
  branchOptions = [{ label: "All branches", value: "" }];
  showTable = false;
  tooltip;

  connectedCallback() {
    if (this.recordId) {
      this.branchId = this.recordId;
    }
    this.loadBranches();
    this.load();
  }

  async loadBranches() {
    try {
      const branches = await getBranches();
      this.branchOptions = [{ label: "All branches", value: "" }, ...branches];
    } catch {
      // The branch list is optional; the dashboard reports real errors.
    }
  }

  async load() {
    try {
      this.data = await getDashboard({
        branchId: this.branchId || null,
        months: Number(this.months)
      });
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  // ---------------------------------------------------------------- formatting

  money(value) {
    return new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency: CURRENCY,
      maximumFractionDigits: 0
    }).format(value || 0);
  }

  compact(value) {
    return new Intl.NumberFormat(LOCALE, {
      notation: "compact",
      maximumFractionDigits: 1
    }).format(value || 0);
  }

  percent(value) {
    return value === null || value === undefined ? "—" : `${value}%`;
  }

  // ---------------------------------------------------------------- state

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.data && !this.errorMessage;
  }
  get tableLabel() {
    return this.showTable ? "Show charts" : "Show as table";
  }
  get showCharts() {
    return !this.showTable;
  }

  get tiles() {
    const d = this.data;
    const tiles = [];
    if (d.showFinance) {
      tiles.push(
        { key: "inv", label: "Invoiced", value: this.money(d.invoicedTotal) },
        { key: "col", label: "Collected", value: this.money(d.collectedTotal) },
        {
          key: "rate",
          label: "Collection rate",
          value: this.percent(d.collectionRate)
        }
      );
    }
    if (d.showEnrolments) {
      tiles.push(
        {
          key: "new",
          label: "New enrolments",
          value: String(d.newEnrolmentsTotal)
        },
        { key: "wd", label: "Withdrawals", value: String(d.withdrawalsTotal) },
        {
          key: "ret",
          label: "Retention (6 cohorts)",
          value: this.percent(d.retentionRate)
        }
      );
    }
    return tiles;
  }

  // ---------------------------------------------------------------- charts

  /** Paired bars for two series per month. */
  pairedBars(first, second, format) {
    const points = this.data.months;
    const max = niceMax(
      Math.max(...points.map((p) => Math.max(p[first] || 0, p[second] || 0)))
    );
    const slot = PLOT_W / points.length;
    const barW = Math.max(2, Math.min(18, (slot - 8 - GAP) / 2));
    const scale = (v) => ((v || 0) / max) * PLOT_H;
    const groups = points.map((p, i) => {
      const left = PAD.left + i * slot + (slot - (2 * barW + GAP)) / 2;
      const h1 = scale(p[first]);
      const h2 = scale(p[second]);
      return {
        key: p.key,
        hitX: PAD.left + i * slot,
        hitW: slot,
        path1: barPath(left, PAD.top + PLOT_H - h1, barW, h1),
        path2: barPath(left + barW + GAP, PAD.top + PLOT_H - h2, barW, h2),
        labelX: PAD.left + i * slot + slot / 2,
        label: p.label,
        showLabel: points.length <= 12 || i % 2 === 0,
        tip: `${p.label}`,
        values: [format(p[first]), format(p[second])]
      };
    });
    return { groups, ticks: this.ticks(max, format) };
  }

  ticks(max, format) {
    return [0, 0.5, 1].map((f) => ({
      key: String(f),
      y: PAD.top + PLOT_H - f * PLOT_H,
      label: format(max * f)
    }));
  }

  get revenueChart() {
    return this.pairedBars("invoiced", "collected", (v) => this.compact(v));
  }

  get enrolmentChart() {
    return this.pairedBars("newEnrolments", "withdrawals", (v) =>
      String(Math.round(v || 0))
    );
  }

  get attendanceChart() {
    const points = this.data.months;
    const slot = PLOT_W / points.length;
    const xy = points.map((p, i) => ({
      key: p.key,
      x: PAD.left + i * slot + slot / 2,
      y:
        p.attendanceRate === null || p.attendanceRate === undefined
          ? null
          : PAD.top + PLOT_H - (p.attendanceRate / 100) * PLOT_H,
      label: p.label,
      showLabel: points.length <= 12 || i % 2 === 0,
      value: this.percent(p.attendanceRate),
      hitX: PAD.left + i * slot,
      hitW: slot
    }));
    const defined = xy.filter((p) => p.y !== null);
    const line = defined
      .map((p, i) => `${i === 0 ? "M" : "L"}${p.x},${p.y}`)
      .join(" ");
    return {
      line,
      dots: defined,
      columns: xy,
      hasData: defined.length > 0,
      ticks: [0, 50, 100].map((v) => ({
        key: String(v),
        y: PAD.top + PLOT_H - (v / 100) * PLOT_H,
        label: `${v}%`
      }))
    };
  }

  get cohorts() {
    return this.data.cohorts.map((c) => {
      const r = c.retention;
      // Sequential single hue: more retention, deeper blue.
      const step = r === null || r === undefined ? 0 : Math.ceil(r / 25);
      return {
        ...c,
        retentionLabel: this.percent(r),
        cellClass: `cohort-cell seq-${step}`,
        empty: !c.enrolled
      };
    });
  }

  get ageing() {
    const max = Math.max(1, ...this.data.ageing.map((b) => b.amount || 0));
    return this.data.ageing.map((b) => ({
      ...b,
      amountLabel: this.money(b.amount),
      barStyle: `width: ${Math.max(b.amount > 0 ? 2 : 0, (b.amount / max) * 100)}%`,
      overdue: b.key !== "current"
    }));
  }

  get courses() {
    return this.data.courses.map((c) => ({
      ...c,
      fill: this.percent(c.fillRate),
      score: this.percent(c.averageScore),
      fillStyle: `width: ${Math.min(Number(c.fillRate) || 0, 100)}%`
    }));
  }
  get hasCourses() {
    return this.data.courses.length > 0;
  }

  get tableRows() {
    return this.data.months.map((p) => ({
      ...p,
      invoicedLabel: this.money(p.invoiced),
      collectedLabel: this.money(p.collected),
      attendanceLabel: this.percent(p.attendanceRate)
    }));
  }

  get viewBox() {
    return `0 0 ${W} ${H}`;
  }
  get baselineY() {
    return PAD.top + PLOT_H;
  }
  get plotLeft() {
    return PAD.left;
  }
  get plotRight() {
    return W - PAD.right;
  }
  get axisLabelY() {
    return H - 8;
  }
  get tickLabelX() {
    return PAD.left - 6;
  }

  // ---------------------------------------------------------------- events

  handleBranch(event) {
    this.branchId = event.detail.value;
    this.load();
  }
  handlePeriod(event) {
    this.months = event.detail.value;
    this.load();
  }
  handleToggleTable() {
    this.showTable = !this.showTable;
  }

  handleHover(event) {
    const { chart, key } = event.currentTarget.dataset;
    const point = this.data.months.find((p) => p.key === key);
    if (!point) {
      return;
    }
    let lines;
    if (chart === "revenue") {
      lines = [
        {
          key: "a",
          swatch: "swatch s1",
          text: `Invoiced ${this.money(point.invoiced)}`
        },
        {
          key: "b",
          swatch: "swatch s2",
          text: `Collected ${this.money(point.collected)}`
        }
      ];
    } else if (chart === "enrolments") {
      lines = [
        { key: "a", swatch: "swatch s1", text: `New ${point.newEnrolments}` },
        {
          key: "b",
          swatch: "swatch s2",
          text: `Withdrawn ${point.withdrawals}`
        }
      ];
    } else {
      lines = [
        {
          key: "a",
          swatch: "swatch s1",
          text: `Attendance ${this.percent(point.attendanceRate)} (${point.attendanceMarks} marks)`
        }
      ];
    }
    const box = event.currentTarget.closest("figure").getBoundingClientRect();
    const target = event.currentTarget.getBoundingClientRect();
    const left = target.left - box.left + target.width / 2;
    this.tooltip = {
      chart,
      title: point.label,
      lines,
      style: `left: ${Math.min(Math.max(left, 70), box.width - 70)}px`
    };
  }

  handleLeave() {
    this.tooltip = undefined;
  }

  get revenueTip() {
    return this.tooltip?.chart === "revenue" ? this.tooltip : null;
  }
  get enrolmentTip() {
    return this.tooltip?.chart === "enrolments" ? this.tooltip : null;
  }
  get attendanceTip() {
    return this.tooltip?.chart === "attendance" ? this.tooltip : null;
  }
}
