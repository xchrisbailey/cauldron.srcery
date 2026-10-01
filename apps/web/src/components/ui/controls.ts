import * as stylex from "@stylexjs/stylex";
import { colors, fonts, type } from "../../styles/tokens.stylex";

// Shared looks for buttons and form controls, so a link styled as a button and a
// select next to an input stay in step.

export const focusRing = stylex.create({
  ring: {
    outline: { default: "none", ":focus-visible": `2px solid ${colors.magic}` },
    outlineOffset: 2,
  },
});

export const control = stylex.create({
  field: {
    width: "100%",
    paddingBlock: 10,
    paddingInline: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: colors.surface1, ":focus-visible": colors.magic },
    backgroundColor: colors.base,
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: 15,
    lineHeight: 1.4,
    outline: { default: "none", ":focus-visible": `2px solid ${colors.magic}` },
    outlineOffset: 1,
  },
  invalid: { borderColor: colors.heat },
  textarea: { minHeight: 96, resize: "vertical", lineHeight: type.bodyLeading },
  select: { appearance: "auto", cursor: "pointer" },
});

export const button = stylex.create({
  base: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    minHeight: 40,
    paddingBlock: 8,
    paddingInline: 16,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "transparent",
    cursor: { default: "pointer", ":disabled": "progress" },
    opacity: { default: 1, ":disabled": 0.7 },
    fontFamily: fonts.ui,
    fontSize: type.controlSize,
    fontWeight: 600,
    lineHeight: 1.2,
    textDecoration: "none",
    whiteSpace: "nowrap",
  },
  primary: { backgroundColor: colors.magic, color: colors.base },
  secondary: {
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    borderColor: colors.surface1,
    color: colors.ink,
  },
  ghost: {
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.ink,
  },
  // Peach text or fill fails contrast in Latte, so danger is an outlined button.
  danger: {
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    borderColor: colors.heat,
    color: colors.ink,
  },
  icon: { minHeight: 36, width: 36, paddingInline: 0, color: colors.subtext },
});

export type ButtonVariant = "primary" | "secondary" | "ghost" | "danger";
