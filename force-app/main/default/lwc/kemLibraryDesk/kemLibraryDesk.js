import { LightningElement, api } from "lwc";
import CURRENCY from "@salesforce/i18n/currency";
import getDesk from "@salesforce/apex/LibraryController.getDesk";
import findLearners from "@salesforce/apex/LibraryController.findLearners";
import addItem from "@salesforce/apex/LibraryController.addItem";
import issue from "@salesforce/apex/LibraryController.issue";
import renew from "@salesforce/apex/LibraryController.renew";
import returnLoan from "@salesforce/apex/LibraryController.returnLoan";
import markLost from "@salesforce/apex/LibraryController.markLost";
import settleFine from "@salesforce/apex/LibraryController.settleFine";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const TYPES = ["Book", "Device", "Kit", "Media", "Other"].map((t) => ({
  label: t,
  value: t
}));

/** Branch library desk. */
export default class KemLibraryDesk extends LightningElement {
  @api recordId;
  data;
  errorMessage;
  hidden = false;
  tab = "loans";
  search = "";
  isBusy = false;
  currencyCode = CURRENCY;
  typeOptions = TYPES;
  // issue form
  issuingItemId;
  learnerSearch = "";
  learnerOptions = [];
  learnerId;
  // add item form
  showAdd = false;
  newItem = { title: "", code: "", type: "Book", author: "", copies: 1 };
  searchTimer;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.data = await getDesk({
        branchId: this.recordId,
        search: this.search
      });
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
  get counts() {
    const d = this.data;
    return [
      { key: "titles", label: "Titles", value: d.titles },
      { key: "copies", label: "Copies", value: d.copies },
      { key: "loan", label: "On loan", value: d.onLoan },
      {
        key: "overdue",
        label: "Overdue",
        value: d.overdue,
        warn: d.overdue > 0
      }
    ].map((c) => ({ ...c, className: `count${c.warn ? " count_warn" : ""}` }));
  }
  tabClass(name) {
    return `tab${this.tab === name ? " tab_active" : ""}`;
  }
  get loansTabClass() {
    return this.tabClass("loans");
  }
  get catalogueTabClass() {
    return this.tabClass("catalogue");
  }
  get finesTabClass() {
    return this.tabClass("fines");
  }
  get isLoans() {
    return this.tab === "loans";
  }
  get isCatalogue() {
    return this.tab === "catalogue";
  }
  get isFines() {
    return this.tab === "fines";
  }
  get loans() {
    return this.data.loans.map((l) => ({
      ...l,
      dueLabel:
        l.daysOverdue > 0
          ? `${l.daysOverdue} day(s) overdue`
          : `Due ${l.dueOn}`,
      dueClass: l.daysOverdue > 0 ? "due due_late" : "due"
    }));
  }
  get hasLoans() {
    return this.data.loans.length > 0;
  }
  get items() {
    return this.data.items.map((i) => ({
      ...i,
      availability: `${i.available} of ${i.copies} available`,
      canIssue: this.data.canLend && i.active && i.available > 0,
      issuing: i.id === this.issuingItemId
    }));
  }
  get hasItems() {
    return this.data.items.length > 0;
  }
  get fines() {
    return this.data.finesDue;
  }
  get hasFines() {
    return this.data.finesDue.length > 0;
  }
  get cannotIssue() {
    return this.isBusy || !this.learnerId;
  }
  get cannotAdd() {
    const i = this.newItem;
    return (
      this.isBusy ||
      !i.title.trim() ||
      !i.code.trim() ||
      !(Number(i.copies) >= 1)
    );
  }

  handleTab(event) {
    this.tab = event.currentTarget.dataset.tab;
  }
  handleRefresh() {
    this.load();
  }
  handleSearch(event) {
    this.search = event.target.value || "";
    window.clearTimeout(this.searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = window.setTimeout(() => this.load(), 300);
  }

  // ---- issue
  handleStartIssue(event) {
    this.issuingItemId = event.currentTarget.dataset.id;
    this.learnerSearch = "";
    this.learnerOptions = [];
    this.learnerId = undefined;
  }
  handleCancelIssue() {
    this.issuingItemId = undefined;
  }
  async handleLearnerSearch(event) {
    this.learnerSearch = event.target.value || "";
    try {
      this.learnerOptions = await findLearners({
        branchId: this.recordId,
        search: this.learnerSearch
      });
    } catch (error) {
      toastError(this, error, "Could not search learners");
    }
  }
  handleLearner(event) {
    this.learnerId = event.detail.value;
  }
  async handleIssue() {
    await this.run(
      () =>
        issue({ itemId: this.issuingItemId, learnerAccountId: this.learnerId }),
      "Item issued",
      "The loan is recorded with its due date."
    );
    this.issuingItemId = undefined;
  }

  // ---- loans
  async handleRenew(event) {
    await this.run(
      () => renew({ loanId: event.currentTarget.dataset.id }),
      "Renewed",
      "The due date was extended."
    );
  }
  async handleReturn(event) {
    const { id, condition } = event.currentTarget.dataset;
    await this.run(
      async () => {
        const fine = await returnLoan({ loanId: id, condition });
        return fine;
      },
      "Returned",
      null,
      (fine) => (fine > 0 ? `Late fine due: ${fine}.` : "Returned on time.")
    );
  }
  async handleLost(event) {
    await this.run(
      () => markLost({ loanId: event.currentTarget.dataset.id }),
      "Marked lost",
      null,
      (fine) => `Charge due: ${fine}.`
    );
  }
  async handleSettle(event) {
    const { id, outcome } = event.currentTarget.dataset;
    await this.run(
      () => settleFine({ loanId: id, outcome }),
      "Fine updated",
      `Fine ${outcome.toLowerCase()}.`
    );
  }

  // ---- add item
  handleToggleAdd() {
    this.showAdd = !this.showAdd;
  }
  handleNewItem(event) {
    const field = event.target.dataset.field;
    const value =
      event.detail?.value !== undefined
        ? event.detail.value
        : event.target.value;
    this.newItem = { ...this.newItem, [field]: value };
  }
  async handleAdd() {
    const i = this.newItem;
    await this.run(
      () =>
        addItem({
          item: {
            Name: i.title.trim(),
            Item_Code__c: i.code.trim(),
            Item_Type__c: i.type,
            Author__c: i.author.trim(),
            Copies_Total__c: Number(i.copies),
            Branch__c: this.recordId
          }
        }),
      "Item added",
      `${i.title.trim()} is in the catalogue.`
    );
    this.showAdd = false;
    this.newItem = { title: "", code: "", type: "Book", author: "", copies: 1 };
  }

  async run(action, title, message, describe) {
    this.isBusy = true;
    try {
      const result = await action();
      toast(this, title, describe ? describe(result) : message);
      await this.load();
    } catch (error) {
      toastError(this, error, `${title} failed`);
    } finally {
      this.isBusy = false;
    }
  }
}
