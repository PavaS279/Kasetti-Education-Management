import { readPdfText, toBytes, MAX_PAGES } from "c/kemPdfText";
import { loadScript } from "lightning/platformResourceLoader";

jest.mock(
  "lightning/platformResourceLoader",
  () => ({ loadScript: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

function page(lines) {
  return {
    getTextContent: () =>
      Promise.resolve({
        items: lines.map((str) => ({ str, hasEOL: true }))
      })
  };
}

describe("c/kemPdfText", () => {
  it("converts base64 and array buffers to bytes", () => {
    expect([...toBytes(window.btoa("AB"))]).toEqual([65, 66]);
    expect(toBytes(new Uint8Array([1, 2]).buffer)).toHaveLength(2);
  });

  it("reads the text of each page up to the limit", async () => {
    const destroy = jest.fn();
    const getDocument = jest.fn(() => ({
      promise: Promise.resolve({
        numPages: MAX_PAGES + 2,
        getPage: (n) => Promise.resolve(page([`Page ${n}`, "Name:  Ananya"])),
        destroy
      })
    }));
    window.pdfjsLib = { GlobalWorkerOptions: {}, getDocument };
    const result = await readPdfText({}, window.btoa("%PDF"));
    expect(loadScript).toHaveBeenCalledWith(
      {},
      expect.stringMatching(/\/pdf\.min\.js$/)
    );
    expect(window.pdfjsLib.GlobalWorkerOptions.workerSrc).toMatch(
      /\/pdf\.worker\.min\.js$/
    );
    expect(getDocument.mock.calls[0][0].isEvalSupported).toBe(false);
    expect(result.pages).toBe(MAX_PAGES);
    expect(result.truncated).toBe(true);
    expect(result.text.startsWith("Page 1\nName: Ananya")).toBe(true);
    expect(destroy).toHaveBeenCalled();
  });
});
