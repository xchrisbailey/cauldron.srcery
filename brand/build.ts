// Draws Cauldron's brand assets from one definition of the mark (the brand
// book's m-pot symbol on its 64×64 grid) for both themes.
import { Resvg } from "@resvg/resvg-js";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const palettes = {
  mocha: {
    bg: "#1e1e2e",
    crust: "#11111b",
    fg: "#cdd6f4",
    mauve: "#cba6f7",
    peach: "#fab387",
    yellow: "#f9e2af",
    pink: "#f5c2e7",
    lavender: "#b4befe",
  },
  latte: {
    bg: "#eff1f5",
    crust: "#dce0e8",
    fg: "#4c4f69",
    mauve: "#8839ef",
    peach: "#fe640b",
    yellow: "#df8e1d",
    pink: "#ea76cb",
    lavender: "#7287fd",
  },
} as const;
type Palette = (typeof palettes)[keyof typeof palettes];

/** The mark's shapes, with colors from `p`. `id` keeps clip-path ids unique when several marks share a document. */
const markBody = (p: Palette, id: string) => `
  <defs><clipPath id="${id}-pot"><path d="M14.5 28.5H49.5V33A17.5 17.5 0 0 1 14.5 33Z"/></clipPath></defs>
  <path fill="${p.peach}" d="M32 51Q39.5 57 37.8 60.6Q36.3 63.6 32 63.6Q27.7 63.6 26.2 60.6Q24.5 57 32 51Z"/>
  <path d="M19.5 49L16.5 58M44.5 49L47.5 58" stroke="${p.fg}" stroke-width="3" stroke-linecap="round" fill="none"/>
  <path d="M13 27H51V33A19 19 0 0 1 13 33Z" fill="${p.bg}" stroke="${p.fg}" stroke-width="3" stroke-linejoin="round"/>
  <path fill="${p.mauve}" clip-path="url(#${id}-pot)" d="M8 36Q14 31.5 20 36T32 36T44 36T56 36V60H8Z"/>
  <circle fill="${p.bg}" fill-opacity=".55" cx="25" cy="43" r="2.6"/>
  <circle fill="${p.bg}" fill-opacity=".55" cx="36" cy="47" r="1.8"/>
  <rect x="9" y="21" width="46" height="7" rx="3.5" fill="${p.bg}" stroke="${p.fg}" stroke-width="3"/>
  <circle fill="${p.mauve}" cx="27" cy="15" r="2.6"/>
  <circle cx="38" cy="11" r="3" stroke="${p.pink}" stroke-width="2" fill="none"/>
  <circle fill="${p.lavender}" cx="45" cy="3.5" r="2.2"/>
  <path fill="${p.yellow}" d="M12 3Q12 8.5 17.5 8.5Q12 8.5 12 14Q12 8.5 6.5 8.5Q12 8.5 12 3Z"/>`;

const svg = (viewBox: string, body: string, extra = "") =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}"${extra}>${body}\n</svg>\n`;

// Just the mark, with a little room for the strokes and the flame.
const mark = (p: Palette) => svg("-1 -1 66 66", markBody(p, "m"));

// The mark beside the wordmark: "cauldron" in Geist 800, the pink ring and
// lavender dot rising out of the o, and a peach cursor.
const lockup = (p: Palette) =>
  svg(
    "0 0 360 80",
    `
  <g transform="translate(4 8)">${markBody(p, "l")}</g>
  <text x="84" y="60" fill="${p.fg}" font-family="Geist, 'Geist Variable', system-ui, sans-serif" font-weight="800" font-size="52" letter-spacing="-2.3">cauldron</text>
  <circle cx="255" cy="22" r="4.4" fill="none" stroke="${p.pink}" stroke-width="2.2"/>
  <circle cx="243" cy="14" r="2.9" fill="${p.lavender}"/>
  <rect x="330" y="55" width="22" height="5" rx="1" fill="${p.peach}"/>`,
  );

// Follows the system theme like srcery.computer's favicon.
const favicon = () => {
  const cls = (p: Palette) =>
    `.o{stroke:${p.fg}}.b{fill:${p.bg}}.l{fill:${p.mauve}}.c{fill:${p.peach}}.y{fill:${p.yellow}}.p{stroke:${p.pink}}.v{fill:${p.lavender}}.bd{fill:${p.bg}}`;
  return svg(
    "-1 -1 66 66",
    `
  <style>${cls(palettes.mocha)}@media (prefers-color-scheme: light){${cls(palettes.latte)}}</style>
  <defs><clipPath id="pot"><path d="M14.5 28.5H49.5V33A17.5 17.5 0 0 1 14.5 33Z"/></clipPath></defs>
  <path class="c" d="M32 51Q39.5 57 37.8 60.6Q36.3 63.6 32 63.6Q27.7 63.6 26.2 60.6Q24.5 57 32 51Z"/>
  <path class="o" d="M19.5 49L16.5 58M44.5 49L47.5 58" stroke-width="3" stroke-linecap="round" fill="none"/>
  <path class="b o" d="M13 27H51V33A19 19 0 0 1 13 33Z" stroke-width="3" stroke-linejoin="round"/>
  <path class="l" clip-path="url(#pot)" d="M8 36Q14 31.5 20 36T32 36T44 36T56 36V60H8Z"/>
  <circle class="bd" fill-opacity=".55" cx="25" cy="43" r="2.6"/><circle class="bd" fill-opacity=".55" cx="36" cy="47" r="1.8"/>
  <rect class="b o" x="9" y="21" width="46" height="7" rx="3.5" stroke-width="3"/>
  <circle class="l" cx="27" cy="15" r="2.6"/>
  <circle class="p" cx="38" cy="11" r="3" stroke-width="2" fill="none"/>
  <circle class="v" cx="45" cy="3.5" r="2.2"/>
  <path class="y" d="M12 3Q12 8.5 17.5 8.5Q12 8.5 12 14Q12 8.5 6.5 8.5Q12 8.5 12 3Z"/>`,
  );
};

/**
 * The app icon: a base-colored square with a faint mauve glow from the top and
 * the mark centered. `maskable` keeps the mark inside the 80% safe zone and
 * leaves the corners square for the platform to mask; otherwise the icon is a
 * squircle like Grimoire's.
 */
const appIcon = (p: Palette, maskable: boolean) => {
  const size = 512;
  const markSize = maskable ? 280 : 340;
  const offset = (size - markSize) / 2;
  const scale = markSize / 66;
  const shape = maskable
    ? `<rect width="${size}" height="${size}" fill="url(#bg)"/>`
    : `<rect width="${size}" height="${size}" rx="${size * 0.225}" fill="url(#bg)"/>`;
  return svg(
    `0 0 ${size} ${size}`,
    `
  <defs>
    <radialGradient id="bg" cx="50%" cy="0%" r="95%" fx="50%" fy="0%">
      <stop offset="0" stop-color="${p.mauve}" stop-opacity=".24"/>
      <stop offset=".55" stop-color="${p.mauve}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="base" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" stop-color="${p.bg}"/><stop offset="1" stop-color="${p.crust}"/></linearGradient>
  </defs>
  ${maskable ? `<rect width="${size}" height="${size}" fill="url(#base)"/>` : `<rect width="${size}" height="${size}" rx="${size * 0.225}" fill="url(#base)"/>`}
  ${shape}
  <g transform="translate(${offset} ${offset}) scale(${scale}) translate(1 1)">${markBody(p, "i")}</g>`,
  );
};

const png = (svgText: string, width: number) =>
  new Resvg(svgText, { fitTo: { mode: "width", value: width }, font: { loadSystemFonts: false } })
    .render()
    .asPng();

// ICO with PNG entries (supported by every current browser and OS).
const ico = (images: ReadonlyArray<{ size: number; data: Buffer }>) => {
  const header = Buffer.alloc(6 + 16 * images.length);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);
  let offset = header.length;
  images.forEach(({ size, data }, i) => {
    const e = 6 + 16 * i;
    header.writeUInt8(size >= 256 ? 0 : size, e);
    header.writeUInt8(size >= 256 ? 0 : size, e + 1);
    header.writeUInt8(0, e + 2);
    header.writeUInt8(0, e + 3);
    header.writeUInt16LE(1, e + 4);
    header.writeUInt16LE(32, e + 6);
    header.writeUInt32LE(data.length, e + 8);
    header.writeUInt32LE(offset, e + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...images.map((i) => i.data)]);
};

const out = process.argv[2] ?? new URL("..", import.meta.url).pathname;
const brandDir = join(out, "brand");
const publicDir = join(out, "apps/web/public");
mkdirSync(brandDir, { recursive: true });
mkdirSync(publicDir, { recursive: true });

writeFileSync(join(brandDir, "mark-dark.svg"), mark(palettes.mocha));
writeFileSync(join(brandDir, "mark-light.svg"), mark(palettes.latte));
writeFileSync(join(brandDir, "lockup-dark.svg"), lockup(palettes.mocha));
writeFileSync(join(brandDir, "lockup-light.svg"), lockup(palettes.latte));
writeFileSync(join(brandDir, "app-icon-dark.svg"), appIcon(palettes.mocha, false));
writeFileSync(join(brandDir, "app-icon-light.svg"), appIcon(palettes.latte, false));
writeFileSync(join(brandDir, "app-icon-maskable.svg"), appIcon(palettes.mocha, true));

writeFileSync(join(publicDir, "favicon.svg"), favicon());
// The .ico is for browsers without SVG favicons; they don't read media queries, so it uses Mocha.
writeFileSync(
  join(publicDir, "favicon.ico"),
  ico([16, 32, 48].map((size) => ({ size, data: png(mark(palettes.mocha), size) }))),
);
writeFileSync(join(publicDir, "apple-touch-icon.png"), png(appIcon(palettes.mocha, true), 180));
writeFileSync(join(publicDir, "icon-192.png"), png(appIcon(palettes.mocha, false), 192));
writeFileSync(join(publicDir, "icon-512.png"), png(appIcon(palettes.mocha, false), 512));
writeFileSync(join(publicDir, "icon-maskable-512.png"), png(appIcon(palettes.mocha, true), 512));
console.log(`Wrote brand assets to ${brandDir} and ${publicDir}`);
