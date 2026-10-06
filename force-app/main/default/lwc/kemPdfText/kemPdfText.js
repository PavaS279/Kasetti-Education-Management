import { loadScript } from "lightning/platformResourceLoader";
import PDFJS from "@salesforce/resourceUrl/pdfjs";

/** Pages read at most: admission documents are short. */
export const MAX_PAGES = 15;

let loading;

function library(component) {
  if (!loading) {
    loading = loadScript(component, `${PDFJS}/pdf.min.js`).then(() => {
      const lib = window.pdfjsLib;
      lib.GlobalWorkerOptions.workerSrc = `${PDFJS}/pdf.worker.min.js`;
      return lib;
    });
    loading.catch(() => {
      loading = undefined;
    });
  }
  return loading;
}

/** Bytes from base64 (Apex) or an ArrayBuffer (file chosen in the browser). */
export function toBytes(source) {
  if (source instanceof ArrayBuffer) {
    return new Uint8Array(source);
  }
  const binary = window.atob(source);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Text of a PDF, read in the browser with pdf.js (text layer only: a
 * scanned image has none). Returns { text, pages, truncated }.
 */
export async function readPdfText(component, source) {
  const lib = await library(component);
  const pdf = await lib.getDocument({
    data: toBytes(source),
    // Text only: no script evaluation, no font loading or extra fetches.
    isEvalSupported: false,
    disableFontFace: true,
    useSystemFonts: false,
    useWorkerFetch: false
  }).promise;
  const pages = Math.min(pdf.numPages, MAX_PAGES);
  const parts = [];
  for (let n = 1; n <= pages; n++) {
    // eslint-disable-next-line no-await-in-loop
    const page = await pdf.getPage(n);
    // eslint-disable-next-line no-await-in-loop
    const content = await page.getTextContent();
    parts.push(
      content.items
        .map((item) => item.str + (item.hasEOL ? "\n" : " "))
        .join("")
        .replace(/[ \t]+/g, " ")
        .trim()
    );
  }
  pdf.destroy();
  return {
    text: parts.join("\n\n").trim(),
    pages,
    truncated: pdf.numPages > MAX_PAGES
  };
}
