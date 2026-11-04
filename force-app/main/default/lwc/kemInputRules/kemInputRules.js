/**
 * Browser-side copies of the server's input rules (InputValidator.cls), so a
 * mistake is shown on the field before anything is sent. The server checks
 * again; these only give earlier feedback.
 */
const NAME = /^\p{L}[\p{L}\p{M} .'-]*$/u;
const EMAIL =
  /^[A-Za-z0-9._%+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
const PHONE = /^\+?[0-9][0-9 ()-]*$/;

export function nameError(value) {
  const v = (value || "").trim();
  if (!v) return "";
  return NAME.test(v) && !v.includes("  ")
    ? ""
    : "Use letters, spaces, apostrophes and hyphens only.";
}

export function emailError(value) {
  const v = (value || "").trim();
  if (!v) return "";
  const local = v.split("@")[0];
  return EMAIL.test(v) &&
    !v.includes("..") &&
    !v.startsWith(".") &&
    !local.endsWith(".")
    ? ""
    : "Enter a valid email address, for example name@example.com.";
}

export function phoneError(value) {
  const v = (value || "").trim();
  if (!v) return "";
  const digits = v.replace(/[^0-9]/g, "").length;
  return PHONE.test(v) && digits >= 10 && digits <= 15
    ? ""
    : "Enter 10 to 15 digits, for example 9876543210 or +91 98765 43210.";
}

const RULES = { name: nameError, email: emailError, phone: phoneError };

/**
 * Applies the rule named in each control's data-rule attribute, then reports
 * validity on every control. Returns true when all are valid.
 */
export function validateControls(controls) {
  return [...controls].reduce((valid, control) => {
    const rule = RULES[control.dataset?.rule];
    if (rule && typeof control.setCustomValidity === "function") {
      control.setCustomValidity(rule(control.value));
    }
    if (typeof control.reportValidity === "function") {
      control.reportValidity();
    }
    const ok =
      typeof control.checkValidity === "function"
        ? control.checkValidity() !== false
        : true;
    return valid && ok;
  }, true);
}
