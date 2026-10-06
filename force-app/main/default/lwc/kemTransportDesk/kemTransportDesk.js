import { LightningElement, api } from "lwc";
import LightningConfirm from "lightning/confirm";
import CURRENCY from "@salesforce/i18n/currency";
import LOCALE from "@salesforce/i18n/locale";
import getRoutes from "@salesforce/apex/TransportController.getRoutes";
import getRoute from "@salesforce/apex/TransportController.getRoute";
import searchLearners from "@salesforce/apex/TransportController.searchLearners";
import assign from "@salesforce/apex/TransportController.assign";
import changeStop from "@salesforce/apex/TransportController.changeStop";
import endAssignment from "@salesforce/apex/TransportController.endAssignment";
import notifyRoute from "@salesforce/apex/TransportController.notifyRoute";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const DIRECTIONS = [
  { label: "Both ways", value: "Both ways" },
  { label: "Morning only", value: "Morning only" },
  { label: "Afternoon only", value: "Afternoon only" }
];

function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Transport desk: routes, the manifest by stop, assigning riders and route notices. */
export default class KemTransportDesk extends LightningElement {
  @api recordId;
  routes;
  detail;
  selectedRouteId;
  errorMessage;
  hidden = false;
  isBusy = false;
  directions = DIRECTIONS;

  // Assign form
  showAssign = false;
  searchTerm = "";
  options = [];
  learnerId;
  stopId;
  direction = "Both ways";
  startDate = today();
  chargeFee = true;

  // Notice form
  showNotice = false;
  notice = "";

  connectedCallback() {
    this.loadRoutes();
  }

  async loadRoutes() {
    try {
      this.routes = await getRoutes({ branchId: this.recordId || null });
      this.errorMessage = undefined;
      if (!this.selectedRouteId && this.routes.length) {
        await this.selectRoute(this.routes[0].routeId);
      }
    } catch (error) {
      const message = reduceErrors(error).join(" ");
      this.hidden = message.includes("do not have access");
      this.errorMessage = message;
    }
  }

  async selectRoute(routeId) {
    this.selectedRouteId = routeId;
    this.showAssign = false;
    this.showNotice = false;
    try {
      this.detail = await getRoute({ routeId });
    } catch (error) {
      toastError(this, error);
    }
  }

  money(value) {
    return new Intl.NumberFormat(LOCALE, {
      style: "currency",
      currency: CURRENCY,
      maximumFractionDigits: 0
    }).format(value || 0);
  }

  // ---------------------------------------------------------------- view

  get visible() {
    return !this.hidden;
  }
  get isLoading() {
    return !this.routes && !this.errorMessage;
  }
  get hasRoutes() {
    return (this.routes || []).length > 0;
  }
  get routeCards() {
    return (this.routes || []).map((r) => {
      const full = r.capacity > 0 && r.riders >= r.capacity;
      return {
        ...r,
        className: `route${r.routeId === this.selectedRouteId ? " route_selected" : ""}${r.active ? "" : " route_inactive"}`,
        seats: `${r.riders} of ${r.capacity} seats`,
        fee: `${this.money(r.monthlyFee)} a month`,
        barStyle: `width:${Math.min(100, r.fillRate || 0)}%`,
        barClass: full ? "bar-fill bar-fill_full" : "bar-fill",
        meta: [r.code, r.vehicle, r.driver].filter((x) => x).join(" · ")
      };
    });
  }
  get route() {
    return this.detail?.route;
  }
  get canManage() {
    return this.detail?.canManage === true;
  }
  get stops() {
    const options = this.stopOptions;
    return (this.detail?.stops || []).map((s) => ({
      ...s,
      times: [
        s.pickupTime ? `pick-up ${s.pickupTime}` : null,
        s.dropTime ? `drop ${s.dropTime}` : null
      ]
        .filter((x) => x)
        .join(" · "),
      count: s.riders.length,
      hasRiders: s.riders.length > 0,
      riders: s.riders.map((r) => ({
        ...r,
        stopOptions: options,
        stopId: s.stopId,
        contact: [r.guardian, r.guardianPhone].filter((x) => x).join(" · ")
      }))
    }));
  }
  get stopOptions() {
    return (this.detail?.stops || []).map((s) => ({
      label: `${s.sequence}. ${s.name}`,
      value: s.stopId
    }));
  }
  get riderCount() {
    return (this.detail?.stops || []).reduce((n, s) => n + s.riders.length, 0);
  }
  get learnerOptions() {
    return this.options.map((o) => ({
      label: o.currentRoute ? `${o.name} (rides ${o.currentRoute})` : o.name,
      value: o.learnerAccountId
    }));
  }
  get hasLearnerOptions() {
    return this.options.length > 0;
  }
  get assignDisabled() {
    return this.isBusy || !this.learnerId || !this.stopId;
  }
  get noticeDisabled() {
    return this.isBusy || this.notice.trim().length < 5;
  }

  // ---------------------------------------------------------------- events

  handleRoute(event) {
    this.selectRoute(event.currentTarget.dataset.id);
  }

  toggleAssign() {
    this.showAssign = !this.showAssign;
    this.showNotice = false;
    this.options = [];
    this.learnerId = undefined;
    this.stopId = this.stopOptions[0]?.value;
  }

  toggleNotice() {
    this.showNotice = !this.showNotice;
    this.showAssign = false;
  }

  async handleSearch(event) {
    this.searchTerm = event.target.value || "";
    if (this.searchTerm.trim().length < 2) {
      this.options = [];
      return;
    }
    try {
      this.options = await searchLearners({
        routeId: this.selectedRouteId,
        term: this.searchTerm
      });
    } catch (error) {
      toastError(this, error);
    }
  }

  handleField(event) {
    const field = event.target.dataset.field;
    this[field] =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.detail.value;
  }

  async handleAssign() {
    await this.run(async () => {
      await assign({
        request: {
          learnerAccountId: this.learnerId,
          routeId: this.selectedRouteId,
          stopId: this.stopId,
          direction: this.direction,
          startDate: this.startDate,
          chargeFee: this.chargeFee
        }
      });
      toast(this, "Learner added to the route", "", "success");
      this.showAssign = false;
    });
  }

  async handleChangeStop(event) {
    const assignmentId = event.target.dataset.id;
    const stopId = event.detail.value;
    await this.run(async () => {
      await changeStop({ assignmentId, stopId });
      toast(this, "Stop changed", "", "success");
    });
  }

  async handleEnd(event) {
    const assignmentId = event.currentTarget.dataset.id;
    const confirmed = await LightningConfirm.open({
      label: "End transport",
      message:
        "End this learner's transport today? The fee stops after this date.",
      theme: "warning"
    });
    if (!confirmed) {
      return;
    }
    await this.run(async () => {
      await endAssignment({ assignmentId, endDate: today(), reason: null });
      toast(this, "Transport ended", "", "success");
    });
  }

  handleNoticeText(event) {
    this.notice = event.target.value || "";
  }

  async handleSendNotice() {
    await this.run(async () => {
      const sent = await notifyRoute({
        routeId: this.selectedRouteId,
        message: this.notice
      });
      toast(
        this,
        "Message sent",
        `${sent} message(s) to families on this route.`,
        "success"
      );
      this.notice = "";
      this.showNotice = false;
    });
  }

  handlePrint() {
    window.print();
  }

  async run(action) {
    this.isBusy = true;
    try {
      await action();
      await this.loadRoutes();
      await this.selectRoute(this.selectedRouteId);
    } catch (error) {
      toastError(this, error);
    } finally {
      this.isBusy = false;
    }
  }
}
