import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vite-plus/test";

// StyleX rewrites the media queries in one value to be mutually exclusive.
// Adding "@media print" beside "(min-width: …)" turns the latter into
// "(min-width: …) and (not (print))", which no browser matches, and the
// desktop layout disappears. Print rules belong in app.css on data-print.
const files = (dir: string): Array<string> =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? files(join(dir, entry.name))
      : /\.tsx?$/.test(entry.name)
        ? [join(dir, entry.name)]
        : [],
  );

describe("StyleX print rules", () => {
  it("never puts @media print in a StyleX value", () => {
    const src = new URL("../src", import.meta.url).pathname;
    const offenders = files(src).filter((file) =>
      /["']@media print["']\s*:/.test(readFileSync(file, "utf8")),
    );
    expect(offenders).toEqual([]);
  });
});
