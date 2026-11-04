import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import getDesk from "@salesforce/apex/CoverController.getDesk";
import assignCover from "@salesforce/apex/CoverController.assignCover";
import cancelForAbsence from "@salesforce/apex/CoverController.cancelForAbsence";
import withdrawAbsence from "@salesforce/apex/CoverController.withdrawAbsence";
import AbsenceModal from "c/kemAbsenceModal";
import ReasonModal from "c/kemReasonModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const STATUS_CLASS = {
  "Needs Cover": "kem-badge kem-badge_danger",
  "Partially Covered": "kem-badge kem-badge_warning",
  Covered: "kem-badge kem-badge_success"
};

const fmt = (value, options) =>
  value
    ? new Intl.DateTimeFormat(undefined, options).format(new Date(value))
    : "";
const when = (value) =>
  fmt(value, {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit"
  });
const time = (value) => fmt(value, { hour: "numeric", minute: "2-digit" });

/** Cover desk: absences and the sessions that still need a cover teacher. */
export default class KemCoverDesk extends NavigationMixin(LightningElement) {
  desk;
  errorMessage;
  isBusy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.desk = await getDesk();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    }
  }

  get absences() {
    const me = this.desk.currentUserId;
    return this.desk.absences.map((a) => {
      const total = a.Sessions_Affected__c || 0;
      const done = a.Sessions_Handled__c || 0;
      return {
        ...a,
        teacher: a.Staff_User__r?.Name,
        period: `${when(a.Start__c)} – ${when(a.End__c)}`,
        statusClass: STATUS_CLASS[a.Status__c] || "kem-badge",
        progress: total
          ? `${done} of ${total} sessions handled`
          : "No sessions in this period",
        barStyle: `width:${total ? Math.round((done / total) * 100) : 100}%`,
        canWithdraw: this.desk.canArrange || a.Staff_User__c === me
      };
    });
  }
  get hasAbsences() {
    return this.desk.absences.length > 0;
  }
  get sessions() {
    return this.desk.uncovered.map((c) => ({
      id: c.session.Id,
      className: c.session.Course_Offering__r?.Name,
      when: `${when(c.session.Start__c)}–${time(c.session.End__c)}`,
      room: c.session.Room__r?.Name || "No room",
      teacher: c.session.Teacher_User__r?.Name,
      learners: c.learners,
      candidates: c.candidates.slice(0, 4).map((t) => ({
        ...t,
        key: `${c.session.Id}-${t.userId}`,
        chipClass: `candidate${t.free ? "" : " candidate_busy"}`,
        detail: t.free
          ? [
              t.taughtCourse ? "has taught this course" : null,
              `${t.sessionsThatDay} other session${t.sessionsThatDay === 1 ? "" : "s"} that day`
            ]
              .filter(Boolean)
              .join(" · ")
          : t.clash,
        assignLabel: `Assign ${t.name}`,
        disabled: !t.free || this.isBusy
      })),
      noCandidates: c.candidates.length === 0
    }));
  }
  get hasSessions() {
    return this.desk.uncovered.length > 0;
  }
  get allClear() {
    return !this.hasAbsences && !this.hasSessions;
  }

  async handleReport() {
    const id = await AbsenceModal.open({
      size: "small",
      teachers: this.desk.teachers,
      canArrange: this.desk.canArrange
    });
    if (id) {
      toast(
        this,
        "Absence recorded",
        "The teacher's sessions are flagged for cover."
      );
      await this.load();
    }
  }

  async run(action, title, message) {
    this.isBusy = true;
    try {
      await action();
      toast(this, title, message);
      await this.load();
    } catch (error) {
      toastError(this, error, "Action failed");
    } finally {
      this.isBusy = false;
    }
  }

  handleAssign(event) {
    const { session, user, name } = event.currentTarget.dataset;
    this.run(
      () => assignCover({ sessionId: session, coverUserId: user, note: null }),
      "Cover assigned",
      `${name} is covering the session and has a task for it.`
    );
  }

  async handleCancelSession(event) {
    const sessionId = event.currentTarget.dataset.session;
    const reason = await ReasonModal.open({
      size: "small",
      label: "Cancel session",
      message: "Families are notified that the session is cancelled.",
      confirmLabel: "Cancel session",
      confirmVariant: "destructive"
    });
    if (reason) {
      this.run(
        () => cancelForAbsence({ sessionId, reason }),
        "Session cancelled",
        "Families have been notified."
      );
    }
  }

  handleWithdraw(event) {
    const absenceId = event.currentTarget.dataset.id;
    this.run(
      () => withdrawAbsence({ absenceId }),
      "Absence withdrawn",
      "Sessions still waiting for cover go back to the teacher."
    );
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
}
