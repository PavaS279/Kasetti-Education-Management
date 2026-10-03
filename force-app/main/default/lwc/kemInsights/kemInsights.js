import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import CURRENCY from "@salesforce/i18n/currency";
import getInsights from "@salesforce/apex/InsightsController.getInsights";
import { reduceErrors } from "c/kemUtils";

function greeting() {
  const hour = new Date().getHours();
  if (hour < 12) {
    return "Good morning";
  }
  return hour < 17 ? "Good afternoon" : "Good evening";
}

function formatTime(value) {
  return new Intl.DateTimeFormat(undefined, { timeStyle: "short" }).format(
    new Date(value)
  );
}

/** Role-aware home cockpit: today's classes and the figures each persona owns. */
export default class KemInsights extends NavigationMixin(LightningElement) {
  currencyCode = CURRENCY;
  data;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getInsights();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get title() {
    return `${greeting()}, ${this.data.userFirstName || "there"}`;
  }
  get todayLabel() {
    return new Intl.DateTimeFormat(undefined, {
      weekday: "long",
      day: "numeric",
      month: "long"
    }).format(new Date());
  }

  get occupancy() {
    const capacity = this.data.seatCapacity || 0;
    return capacity ? Math.round((this.data.seatsTaken / capacity) * 100) : 0;
  }
  get occupancyStyle() {
    return `--value:${this.occupancy}`;
  }
  get attendanceLabel() {
    const rate = this.data.attendanceRate30Days;
    return rate === null || rate === undefined ? "—" : `${Math.round(rate)}%`;
  }
  get attendanceStyle() {
    const rate = this.data.attendanceRate30Days || 0;
    return `--value:${Math.round(rate)}`;
  }

  get admissionsTiles() {
    return [
      {
        key: "open",
        label: "Open enquiries",
        value: this.data.openEnquiries,
        hint: `${this.data.newEnquiriesThisWeek} new this week`,
        target: "KEM_Admissions"
      },
      {
        key: "review",
        label: "Applications in review",
        value: this.data.applicationsInReview,
        hint: `${this.data.readyForDecision} ready for decision`,
        target: "KEM_Applications"
      },
      {
        key: "offers",
        label: "Offers awaiting reply",
        value: this.data.offersAwaitingResponse,
        hint: "Follow up before they expire",
        target: "KEM_Applications"
      }
    ];
  }

  get alerts() {
    const list = [];
    if (this.data.learnersBelowThreshold) {
      list.push({
        key: "attendance",
        icon: "utility:warning",
        text: `${this.data.learnersBelowThreshold} learner(s) below the attendance threshold`
      });
    }
    if (this.data.reconciliationExceptions) {
      list.push({
        key: "recon",
        icon: "utility:error",
        text: `${this.data.reconciliationExceptions} payment(s) need reconciliation`,
        target: "KEM_Finance_Desk"
      });
    }
    if (this.data.discountsAwaitingApproval) {
      list.push({
        key: "discounts",
        icon: "utility:approval",
        text: `${this.data.discountsAwaitingApproval} discount(s) awaiting your approval`
      });
    }
    return list;
  }
  get hasAlerts() {
    return this.alerts.length > 0;
  }

  get sessions() {
    return this.data.todaysSessions.map((s) => {
      const cancelled = s.status === "Cancelled";
      const done = s.attendanceMarked;
      return {
        ...s,
        time: `${formatTime(s.startAt)} – ${formatTime(s.endAt)}`,
        where: [s.room, s.teacher].filter(Boolean).join(" · "),
        badge: cancelled ? "Cancelled" : done ? "Marked" : "To mark",
        badgeClass: cancelled
          ? "kem-badge kem-badge_danger"
          : done
            ? "kem-badge kem-badge_success"
            : "kem-badge kem-badge_warning",
        className: `session${cancelled ? " session_cancelled" : ""}`
      };
    });
  }
  get noSessions() {
    return this.data.todaysSessions.length === 0;
  }
  get hasDashboard() {
    return !!this.data.dashboardId;
  }

  handleTile(event) {
    const target = event.currentTarget.dataset.target;
    if (target) {
      this[NavigationMixin.Navigate]({
        type: "standard__navItemPage",
        attributes: { apiName: target }
      });
    }
  }

  handleSession(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  handleDashboard() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: this.data.dashboardId, actionName: "view" }
    });
  }

  handleTimetable() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName: "KEM_Timetable" }
    });
  }
}
