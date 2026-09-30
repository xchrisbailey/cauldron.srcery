import * as stylex from "@stylexjs/stylex";

// Brand tokens (#1). Colors read the Catppuccin variables in tokens.css, which
// switch between Mocha and Latte with the system theme or the theme toggle;
// no component writes a raw color. Names are the brand book's kitchen roles.

export const colors = stylex.defineVars({
  /** Page background. */
  base: "var(--ctp-base)",
  /** Cards, nav. */
  mantle: "var(--ctp-mantle)",
  crust: "var(--ctp-crust)",
  surface0: "var(--ctp-surface0)",
  surface1: "var(--ctp-surface1)",
  overlay0: "var(--ctp-overlay0)",
  /** Units next to quantities, quiet labels. */
  overlay1: "var(--ctp-overlay1)",
  subtext: "var(--ctp-subtext)",
  /** Text. */
  ink: "var(--ctp-text)",
  /** Primary buttons, selected nav, step numbers, checked ingredients, focus. */
  magic: "var(--ctp-mauve)",
  /** Timers, today in the week, the unsaved dot, the cursor. */
  heat: "var(--ctp-peach)",
  /** Cook's tips, import fields to confirm, the breakfast tag. */
  tips: "var(--ctp-yellow)",
  /** Diet tags, items already in the pantry. */
  fresh: "var(--ctp-green)",
  sparklePink: "var(--ctp-pink)",
  sparkleLavender: "var(--ctp-lavender)",
  // Held for the tracker (#23); don't use elsewhere.
  trackerBlue: "var(--ctp-blue)",
  trackerTeal: "var(--ctp-teal)",
  trackerRed: "var(--ctp-red)",
});

export const fonts = stylex.defineVars({
  /** UI and recipes. */
  ui: "'Geist Variable', Geist, ui-sans-serif, system-ui, sans-serif",
  /** Every quantity, unit, time, serving count and date. */
  mono: "'Geist Mono Variable', 'Geist Mono', ui-monospace, Menlo, monospace",
});

// The brand book's type scale.
export const type = stylex.defineVars({
  titleSize: "34px",
  titleWeight: "700",
  titleTracking: "-0.025em",
  sectionSize: "20px",
  sectionWeight: "650",
  bodySize: "15px",
  bodyLeading: "1.6",
  controlSize: "14px",
  controlWeight: "500",
  quantitySize: "13px",
  quantityWeight: "500",
});

/** Quantities: Geist Mono with tabular numbers; units go in `colors.overlay1`. */
export const quantity = stylex.create({
  value: {
    fontFamily: fonts.mono,
    fontSize: type.quantitySize,
    fontWeight: type.quantityWeight,
    fontVariantNumeric: "tabular-nums",
  },
  unit: { color: colors.overlay1, fontWeight: 400 },
});

/** Base colors for places CSS variables can't reach (the theme-color meta, the web app manifest). */
export const chrome = { mocha: "#1e1e2e" } as const;
