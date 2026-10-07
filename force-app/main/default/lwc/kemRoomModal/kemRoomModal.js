import { api } from "lwc";
import LightningModal from "lightning/modal";
import getChoices from "@salesforce/apex/SiteSetupController.getChoices";
import addRooms from "@salesforce/apex/SiteSetupController.addRooms";
import { newRoom } from "c/kemRoomLines";
import { reduceErrors } from "c/kemUtils";

/** Adds one or more rooms to a branch. Resolves to the number added, or null. */
export default class KemRoomModal extends LightningModal {
  @api branchId;
  selectedBranch;
  branchOptions = [];
  lines = [newRoom()];
  errorMessage;
  isBusy = false;
  isLoading = true;

  get heading() {
    return "Add rooms";
  }

  async connectedCallback() {
    try {
      const choices = await getChoices();
      this.branchOptions = (choices.branches || []).map((b) => ({
        label: b.label,
        value: b.value
      }));
      this.selectedBranch =
        this.branchId ||
        (this.branchOptions.length === 1
          ? this.branchOptions[0].value
          : undefined);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isLoading = false;
    }
  }

  get cannotSave() {
    return (
      this.isBusy ||
      !this.selectedBranch ||
      !this.lines.some((l) => (l.name || "").trim())
    );
  }

  handleBranch(event) {
    this.selectedBranch = event.detail.value;
  }

  handleLines(event) {
    this.lines = event.detail.lines;
  }

  handleCancel() {
    this.close(null);
  }

  async handleSave() {
    if (!this.template.querySelector("c-kem-room-lines").reportValidity()) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const added = await addRooms({
        branchId: this.selectedBranch,
        rooms: this.lines
          .filter((l) => (l.name || "").trim())
          .map((l) => ({
            name: l.name.trim(),
            roomType: l.roomType,
            capacity: l.capacity ? Number(l.capacity) : null,
            equipment: l.equipment,
            meetingUrl: l.meetingUrl
          }))
      });
      this.close(added);
    } catch (error) {
      this.errorMessage = reduceErrors(error).join(" ");
    } finally {
      this.isBusy = false;
    }
  }
}
