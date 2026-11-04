import {
  nameError,
  emailError,
  phoneError,
  validateControls
} from "c/kemInputRules";

describe("c/kemInputRules", () => {
  it("accepts real names and refuses digits and symbols", () => {
    ["Kavya", "D'Souza", "Anne-Marie", "K. Rao", "ಕಾವ್ಯ", ""].forEach((v) =>
      expect(nameError(v)).toBe("")
    );
    ["Kavya123", "<script>", "-Rao", "12", "Kavya  Rao"].forEach((v) =>
      expect(nameError(v)).not.toBe("")
    );
  });

  it("checks email addresses", () => {
    expect(emailError("kavya.rao@example.com")).toBe("");
    ["kavya", "a@b", "a@b.c", "a..b@x.com", "a.@x.com", "a b@x.com"].forEach(
      (v) => expect(emailError(v)).not.toBe("")
    );
  });

  it("needs 10 to 15 digits in a phone number", () => {
    ["9876543210", "+91 98765 43210", "+91-80-1234-5678"].forEach((v) =>
      expect(phoneError(v)).toBe("")
    );
    ["12345", "abc9876543210", "98765x43210", "++919876543210"].forEach((v) =>
      expect(phoneError(v)).not.toBe("")
    );
  });

  it("sets the message on each control and reports the result", () => {
    const control = (rule, value) => {
      let message = "";
      return {
        dataset: { rule },
        value,
        setCustomValidity: jest.fn((m) => {
          message = m;
        }),
        reportValidity: jest.fn(),
        checkValidity: () => message === ""
      };
    };
    const good = control("phone", "9876543210");
    const bad = control("name", "R2D2");
    expect(validateControls([good, bad])).toBe(false);
    expect(bad.setCustomValidity).toHaveBeenCalledWith(
      "Use letters, spaces, apostrophes and hyphens only."
    );
    expect(validateControls([good])).toBe(true);
  });
});
