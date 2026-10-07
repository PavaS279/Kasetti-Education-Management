import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import getPipeline from "@salesforce/apex/EnquiryController.getPipeline";
import getBranches from "@salesforce/apex/EnquiryController.getBranches";
import updateStatus from "@salesforce/apex/EnquiryController.updateStatus";
import LostReasonModal from "c/kemLostReasonModal";
import ConvertModal from "c/kemEnquiryConvertModal";
import EnquiryModal from "c/kemEnquiryModal";
import FamilyModal from "c/kemFamilyModal";
import {
  reduceErrors,
  toast,
  toastError,
  initials,
  toneFor,
  relativeTime,
  followUpClass
} from "c/kemUtils";

const STAGES = ["New", "Contacted", "Nurturing"];

export default class KemEnquiryPipeline extends NavigationMixin(
  LightningElement
) {
  branchId = "";
  mineOnly = false;
  searchTerm = "";
  rawColumns = [];
  branchOptions = [{ label: "All branches", value: "" }];
  errorMessage;
  isLoading = true;
  draggedId;
  dragOverStatus;
  wiredPipeline;

  @wire(getBranches)
  wiredBranches({ data, error }) {
    if (data) {
      this.branchOptions = [
        { label: "All branches", value: "" },
        ...data.map((b) => ({ label: b.Name, value: b.Id }))
      ];
    } else if (error) {
      toastError(this, error, "Branches could not be loaded");
    }
  }

  @wire(getPipeline, { branchId: "$branchParam", mineOnly: "$mineOnly" })
  wiredPipelineResult(result) {
    this.wiredPipeline = result;
    this.isLoading = false;
    if (result.data) {
      this.rawColumns = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = reduceErrors(result.error).join(" ");
    }
  }

  get branchParam() {
    return this.branchId || null;
  }

  get columns() {
    const term = this.searchTerm.trim().toLowerCase();
    return STAGES.map((status) => {
      const source = this.rawColumns.find((c) => c.status === status);
      const cards = (source ? source.enquiries : [])
        .filter((e) => !term || this.matches(e, term))
        .map((e) => this.decorate(e));
      const classes = ["column"];
      if (this.dragOverStatus === status) {
        classes.push("column_drop");
      }
      return {
        status,
        cards,
        count: cards.length,
        isEmpty: cards.length === 0,
        className: classes.join(" ")
      };
    });
  }

  get metrics() {
    const all = this.rawColumns.flatMap((c) => c.enquiries);
    return {
      open: all.length,
      overdue: all.filter((e) => e.Follow_Up_Status__c === "Overdue").length,
      dueToday: all.filter((e) => e.Follow_Up_Status__c === "Due Today").length,
      duplicates: all.filter((e) => e.Possible_Duplicate__c).length
    };
  }

  matches(enquiry, term) {
    return [
      enquiry.Name,
      enquiry.Email,
      enquiry.Phone,
      enquiry.MobilePhone,
      enquiry.Interested_Course__r?.Name
    ]
      .filter(Boolean)
      .some((value) => value.toLowerCase().includes(term));
  }

  decorate(enquiry) {
    const status = enquiry.Follow_Up_Status__c;
    return {
      ...enquiry,
      initials: initials(enquiry.Name),
      avatarClass: `kem-avatar ${toneFor(enquiry.Name)}`,
      courseLabel:
        enquiry.Interested_Course__r?.Name ||
        enquiry.Interested_Program__r?.Name ||
        "Course not selected",
      branchLabel: enquiry.Branch__r?.Name || "No branch",
      ownerLabel: enquiry.Owner?.Name || "",
      followUpClass: followUpClass(status),
      followUpLabel:
        status === "Not Scheduled" || !enquiry.Next_Follow_Up__c
          ? "No follow-up"
          : `${status} · ${relativeTime(enquiry.Next_Follow_Up__c)}`,
      moveOptions: STAGES.filter((s) => s !== enquiry.Status).map((s) => ({
        value: `move:${s}`,
        label: `Move to ${s}`
      }))
    };
  }

  handleBranchChange(event) {
    this.branchId = event.detail.value;
  }

  handleSearch(event) {
    this.searchTerm = event.target.value || "";
  }

  handleMineToggle(event) {
    this.mineOnly = event.target.checked;
  }

  async handleNewEnquiry() {
    const enquiryId = await EnquiryModal.open({
      size: "medium",
      branchId: this.branchId || null
    });
    if (enquiryId) {
      toast(
        this,
        "Enquiry created",
        "It was assigned to a counsellor and appears in the New column."
      );
      await refreshApex(this.wiredPipeline);
    }
  }

  /** A family who walks in ready to join: no enquiry needed. */
  async handleNewFamily() {
    const result = await FamilyModal.open({
      size: "large",
      label: "New family",
      branchId: this.branchId || null
    });
    if (!result?.learnerIds?.length) {
      return;
    }
    const parts = [`${result.created} added`];
    if (result.reused) parts.push(`${result.reused} already on file`);
    if (result.enrolmentIds.length)
      parts.push(`${result.enrolmentIds.length} enrolled`);
    if (result.applicationIds.length)
      parts.push(`${result.applicationIds.length} applications started`);
    toast(this, "Family saved", parts.join(", ") + ".");
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: result.learnerIds[0], actionName: "view" }
    });
  }

  handleRefresh() {
    this.isLoading = true;
    refreshApex(this.wiredPipeline).finally(() => {
      this.isLoading = false;
    });
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        objectApiName: "Lead",
        actionName: "view"
      }
    });
  }

  handleDragStart(event) {
    this.draggedId = event.currentTarget.dataset.id;
    event.dataTransfer.setData("text/plain", this.draggedId);
    event.dataTransfer.effectAllowed = "move";
    event.currentTarget.classList.add("enquiry_dragging");
  }

  handleDragEnd(event) {
    event.currentTarget.classList.remove("enquiry_dragging");
    this.dragOverStatus = undefined;
  }

  handleDragOver(event) {
    event.preventDefault();
    this.dragOverStatus = event.currentTarget.dataset.status;
  }

  handleDragLeave() {
    this.dragOverStatus = undefined;
  }

  async handleDrop(event) {
    event.preventDefault();
    const status = event.currentTarget.dataset.status;
    const id = event.dataTransfer.getData("text/plain") || this.draggedId;
    this.dragOverStatus = undefined;
    await this.moveTo(id, status);
  }

  async handleMenuSelect(event) {
    const id = event.currentTarget.dataset.id;
    const action = event.detail.value;
    if (action.startsWith("move:")) {
      await this.moveTo(id, action.substring(5));
    } else if (action === "unqualified") {
      await this.markUnqualified(id);
    } else if (action === "convert") {
      await this.convert(id);
    }
  }

  async moveTo(id, status) {
    const current = this.rawColumns
      .flatMap((c) => c.enquiries)
      .find((e) => e.Id === id);
    if (!current || current.Status === status) {
      return;
    }
    const previous = this.rawColumns;
    // Optimistic move so the board responds instantly.
    this.rawColumns = this.rawColumns.map((column) => {
      if (column.status === current.Status) {
        return {
          ...column,
          enquiries: column.enquiries.filter((e) => e.Id !== id)
        };
      }
      if (column.status === status) {
        return {
          ...column,
          enquiries: [{ ...current, Status: status }, ...column.enquiries]
        };
      }
      return column;
    });
    try {
      await updateStatus({ leadId: id, status, lostReason: null });
      toast(this, "Enquiry updated", `${current.Name} moved to ${status}.`);
      await refreshApex(this.wiredPipeline);
    } catch (error) {
      this.rawColumns = previous;
      toastError(this, error, "Enquiry could not be moved");
    }
  }

  async markUnqualified(id) {
    const reason = await LostReasonModal.open({
      size: "small",
      label: "Mark enquiry as unqualified"
    });
    if (!reason) {
      return;
    }
    try {
      await updateStatus({
        leadId: id,
        status: "Unqualified",
        lostReason: reason
      });
      toast(this, "Enquiry closed", "The enquiry was marked as unqualified.");
      await refreshApex(this.wiredPipeline);
    } catch (error) {
      toastError(this, error, "Enquiry could not be closed");
    }
  }

  async convert(id) {
    const result = await ConvertModal.open({
      size: "medium",
      label: "Convert enquiry",
      recordId: id
    });
    if (result?.learnerId) {
      await refreshApex(this.wiredPipeline);
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: result.learnerId,
          objectApiName: "Account",
          actionName: "view"
        }
      });
    }
  }
}
