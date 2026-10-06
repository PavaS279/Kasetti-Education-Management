import { LightningElement, api, wire } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import LOCALE from "@salesforce/i18n/locale";
import getForecast from "@salesforce/apex/ForecastController.getForecast";
import explainForecast from "@salesforce/apex/ForecastController.explainForecast";
import getBranches from "@salesforce/apex/AnalyticsController.getBranches";
import isAvailable from "@salesforce/apex/AiController.isAvailable";
import review from "@salesforce/apex/AiController.review";
import { reduceErrors } from "c/kemUtils";

// Chart geometry (SVG user units; the SVG scales to its container).
const W = 640;
const H = 200;
const PAD = { top: 12, right: 8, bottom: 28, left: 48 };
const PLOT_W = W - PAD.left - PAD.right;
const PLOT_H = H - PAD.top - PAD.bottom;
const RADIUS = 3;

const HORIZONS = [
  { label: "3 months", value: "3" },
  { label: "6 months", value: "6" }
];

const STATUS_CLASS = { Short: "chip chip_bad", Tight: "chip chip_warn" };

function niceMax(value) {
  if (!value || value <= 0) {
    return 1;
  }
  const magnitude = 10 ** Math.floor(Math.log10(value));
  for (const step of [1, 2, 2.5, 5, 10]) {
    if (step * magnitude >= value) {
      return step * magnitude;
    }
  }
  return 10 * magnitude;
}

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

function accuracyClass(accuracy) {
  if (accuracy === "Good") {
    return "chip chip_good";
  }
  if (accuracy === "Fair") {
    return "chip chip_warn";
  }
  return "chip";
}

/**
 * Planning forecasts: new enrolments and seats, invoicing and expected
 * cash, with the backtest accuracy, the admissions pipeline and an
 * optional Einstein explanation.
 */
export default class KemForecast extends LightningElement {
  @api recordId;
  data;
  errorMessage;
  hidden = false;
  branchId = "";
  horizon = "3";
  horizonOptions = HORIZONS;
  branchOptions = [{ label: "All branches", value: "" }];
  aiAvailable = false;
  narrative;
  narrativeError;
  isExplaining = false;
  reviewed = false;

  @wire(isAvailable, { feature: "Forecast Narrative" })
  wiredAi({ data }) {
    this.aiAvailable = data === true;
  }

  connectedCallback() {
    if (this.recordId) {
      this.branchId = this.recordId;
    } else {
      this.loadBranches();
    }
    this.load();
  }

  async loadBranches() {
    try {
      const branches = await getBranches();
      this.branchOptions = [{ label: "All branches", value: "" }, ...branches];
    } catch {
      // The branch list is optional.
    }
  }

  async load() {
    try {
      this.data = await getForecast({
        branchId: this.branchId || null,
        horizon: Number(this.horizon)
      });
      this.errorMessage = undefined;
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  // ---------------------------------------------------------------- state

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.data && !this.errorMessage;
  }
  get showBranchPicker() {
    return !this.recordId;
  }
  get hasNothing() {
    return this.data && !this.data.showEnrolments && !this.data.showFinance;
  }
  get hasNotes() {
    return (this.data?.notes || []).length > 0;
  }
  get notes() {
    return (this.data?.notes || []).map((text, i) => ({
      key: String(i),
      text
    }));
  }
  get months() {
    return Number(this.horizon);
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

  change(series) {
    if (series?.change === null || series?.change === undefined) {
      return "";
    }
    const sign = series.change > 0 ? "+" : "";
    return `${sign}${series.change}% vs last ${this.months} months`;
  }

  // ---------------------------------------------------------------- tiles

  get tiles() {
    const d = this.data;
    const tiles = [];
    if (d?.showEnrolments) {
      const short = d.seats.filter((s) => s.status === "Short").length;
      tiles.push(
        {
          key: "enrol",
          label: `New enrolments, next ${this.months} months`,
          value: String(d.enrolments.nextTotal),
          sub: this.change(d.enrolments)
        },
        {
          key: "pipeline",
          label: "Expected from the pipeline",
          value: String(d.pipelineExpected),
          sub: "enquiries, applications, offers, waitlist"
        },
        {
          key: "seats",
          label: "Courses short of seats",
          value: String(short),
          sub: short ? "open another class" : "enough seats",
          warn: short > 0
        }
      );
    }
    if (d?.showFinance) {
      const cash = d.cash.reduce((sum, c) => sum + (c.expectedCash || 0), 0);
      tiles.push(
        {
          key: "invoiced",
          label: `Invoicing, next ${this.months} months`,
          value: this.money(d.revenue.nextTotal),
          sub: this.change(d.revenue)
        },
        {
          key: "cash",
          label: "Expected cash",
          value: this.money(cash),
          sub:
            d.collectionRate === null || d.collectionRate === undefined
              ? "collection rate not known yet"
              : `at ${d.collectionRate}% collection`
        },
        {
          key: "open",
          label: "Open receivables",
          value: this.money(d.openReceivables),
          sub: "invoices and instalments due"
        }
      );
    }
    return tiles.map((t) => ({
      ...t,
      className: `tile${t.warn ? " tile_warn" : ""}`
    }));
  }

  // ---------------------------------------------------------------- charts

  chart(series, format) {
    if (!series) {
      return null;
    }
    const points = series.points;
    const max = niceMax(
      Math.max(
        ...points.map((p) =>
          Math.max(p.actual || 0, p.high || 0, p.forecast || 0)
        )
      )
    );
    const slot = PLOT_W / points.length;
    const barW = Math.max(4, Math.min(22, slot - 8));
    const y = (v) => PAD.top + PLOT_H - ((v || 0) / max) * PLOT_H;
    const bars = points.map((p, i) => {
      const x = PAD.left + i * slot + (slot - barW) / 2;
      const value = p.isFuture ? p.forecast : p.actual;
      const top = y(value);
      const bar = {
        key: p.key,
        path: barPath(x, top, barW, PAD.top + PLOT_H - top),
        className: p.isFuture ? "bar bar_future" : "bar",
        labelX: PAD.left + i * slot + slot / 2,
        label: p.label,
        showLabel: points.length <= 9 || i % 2 === 0 || p.isFuture,
        title: p.isFuture
          ? `${p.label}: forecast ${format(p.forecast)} (range ${format(p.low)}–${format(p.high)})`
          : `${p.label}: ${format(p.actual)}`,
        hasRange: p.isFuture && p.high > p.low,
        rangeX: x + barW / 2,
        rangeTop: y(p.high),
        rangeBottom: y(p.low),
        capLeft: x + barW / 2 - 4,
        capRight: x + barW / 2 + 4
      };
      return bar;
    });
    const firstFuture = points.findIndex((p) => p.isFuture);
    return {
      bars,
      ticks: [0, 0.5, 1].map((f) => ({
        key: String(f),
        y: PAD.top + PLOT_H - f * PLOT_H,
        label: format(max * f)
      })),
      dividerX: firstFuture > 0 ? PAD.left + firstFuture * slot : null,
      accuracy: series.accuracy,
      accuracyClass: accuracyClass(series.accuracy),
      method: series.method,
      detail:
        series.mape === null || series.mape === undefined
          ? `${series.historyMonths} months of history`
          : `backtest error ${series.mape}% · ${series.historyMonths} months of history`,
      table: points.map((p) => ({
        key: p.key,
        label: p.label,
        value: p.isFuture ? format(p.forecast) : format(p.actual),
        range: p.isFuture ? `${format(p.low)}–${format(p.high)}` : "",
        kind: p.isFuture ? "Forecast" : "Actual"
      }))
    };
  }

  get enrolmentChart() {
    return this.chart(this.data?.enrolments, (v) => String(Math.round(v || 0)));
  }
  get revenueChart() {
    return this.chart(this.data?.revenue, (v) => this.compact(v));
  }
  get viewBox() {
    return `0 0 ${W} ${H}`;
  }
  get axisY() {
    return PAD.top + PLOT_H;
  }
  get axisLeft() {
    return PAD.left;
  }
  get axisRight() {
    return W - PAD.right;
  }
  get labelY() {
    return H - 8;
  }
  get dividerTop() {
    return PAD.top;
  }

  // ---------------------------------------------------------------- tables

  get pipelineRows() {
    return (this.data?.pipeline || []).map((r) => ({
      ...r,
      rateLabel: `${r.rate}%${r.assumed ? " (assumed)" : ""}`
    }));
  }
  get seatRows() {
    return (this.data?.seats || []).map((s) => ({
      ...s,
      statusClass: STATUS_CLASS[s.status] || "chip chip_good"
    }));
  }
  get hasSeats() {
    return this.seatRows.length > 0;
  }
  get cashRows() {
    return (this.data?.cash || []).map((c) => ({
      ...c,
      due: this.money(c.dueFromOpen),
      billing: this.money(c.committedBilling),
      expected: this.money(c.expectedCash)
    }));
  }

  // ---------------------------------------------------------------- events

  handleBranch(event) {
    this.branchId = event.detail.value;
    this.resetNarrative();
    this.load();
  }

  handleHorizon(event) {
    this.horizon = event.detail.value;
    this.resetNarrative();
    this.load();
  }

  handleRefresh() {
    this.load();
  }

  resetNarrative() {
    this.narrative = undefined;
    this.narrativeError = undefined;
    this.reviewed = false;
  }

  async handleExplain() {
    this.isExplaining = true;
    this.narrativeError = undefined;
    this.reviewed = false;
    try {
      this.narrative = await explainForecast({
        branchId: this.branchId || null,
        horizon: Number(this.horizon)
      });
    } catch (error) {
      this.narrativeError = reduceErrors(error).join(" ");
    } finally {
      this.isExplaining = false;
    }
  }

  get narrativeParagraphs() {
    return (this.narrative?.text || "")
      .split(/\n+/)
      .filter((p) => p.trim())
      .map((text, i) => ({ key: String(i), text }));
  }

  async handleFeedback(event) {
    const helpful = event.currentTarget.dataset.helpful === "true";
    try {
      await review({
        interactionId: this.narrative.interactionId,
        outcome: helpful ? "Accepted" : "Rejected",
        finalText: helpful ? this.narrative.text : null,
        rating: helpful ? 5 : 2,
        feedback: null
      });
    } catch {
      // Feedback is optional.
    }
    this.reviewed = true;
  }
}
