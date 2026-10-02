// Stub of lightning/confirm: resolves to the value configured on the mock.
export default class LightningConfirm {
  static result = true;
  static open = jest.fn(() => Promise.resolve(LightningConfirm.result));
}
