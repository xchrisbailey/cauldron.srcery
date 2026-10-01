import * as stylex from "@stylexjs/stylex";
import { Link } from "@tanstack/react-router";
import type { ComponentProps, ReactNode } from "react";
import { colors, type } from "../../styles/tokens.stylex";
import { Mark } from "../Mark";
import { focusRing } from "./controls";

/** The card the sign-in, sign-up and account screens sit in. */
export function AuthCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section {...stylex.props(styles.card)}>
      <Mark size={40} />
      <h1 {...stylex.props(styles.cardTitle)}>{title}</h1>
      {children}
    </section>
  );
}

/** A page's title row in the signed-in app, with optional actions on the right. */
export function PageHeader({ title, actions }: { title: string; actions?: ReactNode }) {
  return (
    <header {...stylex.props(styles.header)}>
      <h1 {...stylex.props(styles.pageTitle)}>{title}</h1>
      {actions ? <div {...stylex.props(styles.actions)}>{actions}</div> : null}
    </header>
  );
}

export function FormMessage({ tone, children }: { tone: "error" | "info"; children: ReactNode }) {
  return (
    <p
      role={tone === "error" ? "alert" : "status"}
      {...stylex.props(styles.message, tone === "error" && styles.messageError)}
    >
      {children}
    </p>
  );
}

export function TextLink(props: ComponentProps<typeof Link>) {
  return <Link {...props} {...stylex.props(styles.link, focusRing.ring)} />;
}

export function Divider({ label }: { label: string }) {
  return <p {...stylex.props(styles.divider)}>{label}</p>;
}

export function Stack({ children }: { children: ReactNode }) {
  return <div {...stylex.props(styles.stack)}>{children}</div>;
}

const styles = stylex.create({
  card: {
    width: "100%",
    maxWidth: 400,
    display: "flex",
    flexDirection: "column",
    gap: 16,
    padding: { default: 28, "@media (max-width: 480px)": 20 },
    borderRadius: 16,
    backgroundColor: colors.mantle,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
  },
  cardTitle: { margin: 0, fontSize: 22, fontWeight: 650, letterSpacing: "-0.01em" },
  header: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "flex-end",
    justifyContent: "space-between",
    gap: 16,
  },
  pageTitle: {
    margin: 0,
    fontSize: { default: type.titleSize, "@media (max-width: 767px)": 28 },
    fontWeight: type.titleWeight,
    letterSpacing: type.titleTracking,
    lineHeight: 1.1,
  },
  actions: { display: "flex", flexWrap: "wrap", gap: 8 },
  stack: { display: "flex", flexDirection: "column", gap: 12 },
  message: { margin: 0, fontSize: 14, color: colors.subtext },
  // Plain ink with a peach rule: peach text is too faint on Latte.
  messageError: {
    color: colors.ink,
    paddingInlineStart: 10,
    borderInlineStartWidth: 3,
    borderInlineStartStyle: "solid",
    borderInlineStartColor: colors.heat,
  },
  // Ink with a mauve underline: mauve text on mantle is under 4.5:1 in Latte.
  link: {
    color: colors.ink,
    fontSize: 14,
    borderRadius: 4,
    textDecorationLine: "underline",
    textDecorationColor: colors.magic,
    textDecorationThickness: { default: 1.5, ":hover": 2.5 },
    textUnderlineOffset: 3,
  },
  divider: { margin: 0, textAlign: "center", fontSize: 13, color: colors.subtext },
});
