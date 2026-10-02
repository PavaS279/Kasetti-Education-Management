import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import CURRENCY from "@salesforce/i18n/currency";
import getCoursePrices from "@salesforce/apex/PricingController.getCoursePrices";
import getQuote from "@salesforce/apex/PricingController.getQuote";
import endPrice from "@salesforce/apex/PricingController.endPrice";
import getBranches from "@salesforce/apex/EnquiryController.getBranches";
import PriceModal from "c/kemPriceModal";
import { reduceErrors, toast, toastError } from "c/kemUtils";

const QUOTE_DELAY = 350;
const MODES = ["Classroom", "Online", "Hybrid"];

function iso(date) {
  return date.toISOString().slice(0, 10);
}

function formatDate(value) {
  return value
    ? new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
        new Date(value)
      )
    : "";
}

export default class KemCoursePricing extends LightningElement {
  @api recordId;
  currencyCode = CURRENCY;
  prices = [];
  branchOptions = [{ label: "Any branch (global prices)", value: "" }];
  branchId = "";
  deliveryMode = "Classroom";
  quoteDate = iso(new Date());
  discountCode = "";
  quote;
  quoteError;
  wiredPrices;
  quoteTimer;

  @wire(getCoursePrices, { courseId: "$recordId" })
  wiredPriceList(result) {
    this.wiredPrices = result;
    if (result.data) {
      this.prices = result.data;
      this.scheduleQuote();
    } else if (result.error) {
      toastError(this, result.error, "Prices could not be loaded");
    }
  }

  @wire(getBranches)
  wiredBranches({ data }) {
    if (data) {
      this.branchOptions = [
        { label: "Any branch (global prices)", value: "" },
        ...data.map((b) => ({ label: b.Name, value: b.Id }))
      ];
    }
  }

  get modeOptions() {
    return MODES.map((m) => ({ label: m, value: m }));
  }

  get activeCount() {
    return this.priceCards.filter((p) => p.state === "Active").length;
  }

  get noPrices() {
    return this.prices.length === 0;
  }

  get priceCards() {
    const today = iso(new Date());
    return this.prices.map((p) => {
      let state = "Active";
      if (!p.Active__c) {
        state = "Inactive";
      } else if (p.Effective_From__c > today) {
        state = "Scheduled";
      } else if (p.Effective_To__c && p.Effective_To__c < today) {
        state = "Ended";
      }
      const stateClass = {
        Active: "kem-badge kem-badge_success",
        Scheduled: "kem-badge kem-badge_info",
        Ended: "kem-badge",
        Inactive: "kem-badge"
      }[state];
      return {
        ...p,
        state,
        stateClass,
        cardClass: `price kem-card ${state === "Active" ? "price_active" : "price_muted"}`,
        period: `${formatDate(p.Effective_From__c)} → ${p.Effective_To__c ? formatDate(p.Effective_To__c) : "open-ended"}`,
        branchLabel: p.Branch__r?.Name || "All branches",
        modeLabel: p.Delivery_Mode__c || "All modes",
        canEnd: state === "Active" && !p.Effective_To__c
      };
    });
  }

  handleBranch(event) {
    this.branchId = event.detail.value;
    this.scheduleQuote();
  }
  handleMode(event) {
    this.deliveryMode = event.detail.value;
    this.scheduleQuote();
  }
  handleDate(event) {
    this.quoteDate = event.target.value;
    this.scheduleQuote();
  }
  handleCode(event) {
    this.discountCode = event.target.value;
    this.scheduleQuote();
  }

  scheduleQuote() {
    clearTimeout(this.quoteTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.quoteTimer = setTimeout(() => this.runQuote(), QUOTE_DELAY);
  }

  async runQuote() {
    try {
      this.quote = await getQuote({
        request: {
          courseId: this.recordId,
          branchId: this.branchId || null,
          deliveryMode: this.deliveryMode,
          onDate: this.quoteDate,
          discountCode: this.discountCode
        }
      });
      this.quoteError = undefined;
    } catch (error) {
      this.quote = undefined;
      this.quoteError = reduceErrors(error).join(" ");
    }
  }

  async handleNewPrice() {
    const id = await PriceModal.open({
      size: "medium",
      label: "New price",
      courseId: this.recordId
    });
    if (id) {
      toast(
        this,
        "Price saved",
        "The new price is available for quotes and enrolments."
      );
      await refreshApex(this.wiredPrices);
    }
  }

  async handleEndPrice(event) {
    const priceId = event.currentTarget.dataset.id;
    try {
      await endPrice({ priceId, endDate: iso(new Date()) });
      toast(
        this,
        "Price ended",
        "The price ends today. Add a replacement starting tomorrow."
      );
      await refreshApex(this.wiredPrices);
    } catch (error) {
      toastError(this, error, "Price could not be ended");
    }
  }
}
