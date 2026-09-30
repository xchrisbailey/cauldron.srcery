import * as stylex from "@stylexjs/stylex";

// Spike subset of the brand tokens (#1 owns the full set). Mocha by default,
// Latte when the system prefers light.
const LIGHT = "@media (prefers-color-scheme: light)";

export const colors = stylex.defineVars({
  base: { default: "#1e1e2e", [LIGHT]: "#eff1f5" },
  mantle: { default: "#181825", [LIGHT]: "#e6e9ef" },
  surface0: { default: "#313244", [LIGHT]: "#ccd0da" },
  subtext: { default: "#a6adc8", [LIGHT]: "#6c6f85" },
  ink: { default: "#cdd6f4", [LIGHT]: "#4c4f69" },
  magic: { default: "#cba6f7", [LIGHT]: "#8839ef" },
  heat: { default: "#fab387", [LIGHT]: "#fe640b" },
  fresh: { default: "#a6e3a1", [LIGHT]: "#40a02b" },
});

export const fonts = stylex.defineVars({
  ui: "Geist, ui-sans-serif, system-ui, sans-serif",
  mono: "'Geist Mono', ui-monospace, monospace",
});
