/**
 * Shared helpers for Kasetti Education Management components.
 */
import { ShowToastEvent } from "lightning/platformShowToastEvent";

/** Flattens Lightning/Apex errors into readable messages. */
export function reduceErrors(errors) {
  const list = Array.isArray(errors) ? errors : [errors];
  return list
    .filter((error) => !!error)
    .map((error) => {
      if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message);
      }
      if (error.body?.pageErrors?.length) {
        return error.body.pageErrors.map((e) => e.message);
      }
      if (
        error.body?.fieldErrors &&
        Object.keys(error.body.fieldErrors).length
      ) {
        return Object.values(error.body.fieldErrors)
          .flat()
          .map((e) => e.message);
      }
      if (error.body?.message) {
        return error.body.message;
      }
      return error.message || String(error);
    })
    .flat()
    .filter((message) => !!message);
}

export function toast(component, title, message, variant = "success") {
  component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}

export function toastError(component, error, title = "Something went wrong") {
  toast(component, title, reduceErrors(error).join(" "), "error");
}

export function initials(name) {
  if (!name) {
    return "?";
  }
  const parts = name.trim().split(/\s+/);
  return (
    (parts[0]?.[0] || "") + (parts.length > 1 ? parts[parts.length - 1][0] : "")
  ).toUpperCase();
}

const AVATAR_TONES = [
  "tone-1",
  "tone-2",
  "tone-3",
  "tone-4",
  "tone-5",
  "tone-6"
];

/** Picks a stable avatar colour class from a string. */
export function toneFor(value) {
  let hash = 0;
  for (const ch of value || "") {
    hash = (hash * 31 + ch.charCodeAt(0)) % 997;
  }
  return AVATAR_TONES[hash % AVATAR_TONES.length];
}

/** "in 3h", "2d ago", "today" style relative time. */
export function relativeTime(value) {
  if (!value) {
    return "";
  }
  const diffMs = new Date(value).getTime() - Date.now();
  const abs = Math.abs(diffMs);
  const minutes = Math.round(abs / 60000);
  const hours = Math.round(abs / 3600000);
  const days = Math.round(abs / 86400000);
  let label;
  if (minutes < 60) {
    label = `${minutes}m`;
  } else if (hours < 24) {
    label = `${hours}h`;
  } else {
    label = `${days}d`;
  }
  return diffMs >= 0 ? `in ${label}` : `${label} ago`;
}

export function formatDateTime(value) {
  if (!value) {
    return "";
  }
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(new Date(value));
}

/** Badge variant class for a follow-up status formula value. */
export function followUpClass(status) {
  switch (status) {
    case "Overdue":
      return "kem-badge kem-badge_danger";
    case "Due Today":
      return "kem-badge kem-badge_warning";
    case "Scheduled":
      return "kem-badge kem-badge_success";
    default:
      return "kem-badge";
  }
}
