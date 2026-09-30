import * as stylex from "@stylexjs/stylex";
import type { AnyFieldApi } from "@tanstack/react-form";
import { Link } from "@tanstack/react-router";
import type { ComponentProps, ReactNode } from "react";
import { colors, fonts } from "../styles/tokens.stylex";

// Minimal building blocks for the account screens. #7 brings the app shell.

export function AuthCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <main {...stylex.props(styles.page)}>
      <section {...stylex.props(styles.card)}>
        <h1 {...stylex.props(styles.title)}>{title}</h1>
        {children}
      </section>
    </main>
  );
}

const issueText = (issue: unknown) =>
  typeof issue === "string"
    ? issue
    : typeof issue === "object" && issue !== null && "message" in issue
      ? String(issue.message)
      : "";

export function TextField({
  field,
  label,
  type = "text",
  autoComplete,
}: {
  field: AnyFieldApi;
  label: string;
  type?: "text" | "email" | "password";
  autoComplete?: string;
}) {
  const errors =
    field.state.meta.isTouched || field.form.state.submissionAttempts > 0
      ? field.state.meta.errors
      : [];
  const message = errors.map(issueText).find(Boolean);
  return (
    <label {...stylex.props(styles.field)}>
      <span {...stylex.props(styles.label)}>{label}</span>
      <input
        {...stylex.props(styles.input, message ? styles.inputInvalid : null)}
        name={field.name}
        type={type}
        autoComplete={autoComplete}
        value={field.state.value as string}
        onBlur={field.handleBlur}
        onChange={(e) => field.handleChange(e.target.value)}
        aria-invalid={message ? true : undefined}
      />
      {message ? <span {...stylex.props(styles.fieldError)}>{message}</span> : null}
    </label>
  );
}

export function Button({
  variant = "primary",
  ...props
}: ComponentProps<"button"> & { variant?: "primary" | "secondary" | "danger" }) {
  return <button {...props} {...stylex.props(styles.button, styles[variant])} />;
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
  return <Link {...props} {...stylex.props(styles.link)} />;
}

export function Divider({ label }: { label: string }) {
  return <p {...stylex.props(styles.divider)}>{label}</p>;
}

export function Stack({ children }: { children: ReactNode }) {
  return <div {...stylex.props(styles.stack)}>{children}</div>;
}

const styles = stylex.create({
  page: {
    minHeight: "100vh",
    display: "grid",
    placeItems: "center",
    padding: 16,
  },
  card: {
    width: "100%",
    maxWidth: 400,
    display: "flex",
    flexDirection: "column",
    gap: 16,
    padding: 28,
    borderRadius: 16,
    backgroundColor: colors.mantle,
  },
  title: { margin: 0, fontSize: 22, fontWeight: 650, letterSpacing: "-0.01em" },
  stack: { display: "flex", flexDirection: "column", gap: 12 },
  field: { display: "flex", flexDirection: "column", gap: 6 },
  label: { fontSize: 14, fontWeight: 500, color: colors.subtext },
  input: {
    paddingBlock: 10,
    paddingInline: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.base,
    color: colors.ink,
    fontFamily: fonts.ui,
    fontSize: 15,
    outline: { default: "none", ":focus-visible": `2px solid ${colors.magic}` },
    outlineOffset: 1,
  },
  inputInvalid: { borderColor: colors.heat },
  fieldError: { fontSize: 13, color: colors.heat },
  button: {
    paddingBlock: 10,
    paddingInline: 16,
    borderRadius: 10,
    borderWidth: 0,
    cursor: { default: "pointer", ":disabled": "progress" },
    opacity: { default: 1, ":disabled": 0.7 },
    fontFamily: fonts.ui,
    fontSize: 14,
    fontWeight: 500,
    outline: { default: "none", ":focus-visible": `2px solid ${colors.magic}` },
    outlineOffset: 2,
  },
  primary: { backgroundColor: colors.magic, color: colors.base },
  secondary: { backgroundColor: colors.surface0, color: colors.ink },
  danger: { backgroundColor: colors.heat, color: colors.base },
  message: { margin: 0, fontSize: 14, color: colors.subtext },
  messageError: { color: colors.heat },
  link: {
    color: colors.magic,
    fontSize: 14,
    textDecoration: { default: "none", ":hover": "underline" },
  },
  divider: { margin: 0, textAlign: "center", fontSize: 13, color: colors.subtext },
});
