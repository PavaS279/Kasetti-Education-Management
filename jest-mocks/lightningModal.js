// Minimal stub of lightning/modal for unit tests: open() resolves to the value set on the mock.
import { LightningElement, api } from "lwc";

export default class LightningModal extends LightningElement {
  static openResult = undefined;
  static open = jest.fn(() => Promise.resolve(LightningModal.openResult));
  @api disableClose;
  close(result) {
    this.dispatchEvent(new CustomEvent("close", { detail: result }));
  }
}
