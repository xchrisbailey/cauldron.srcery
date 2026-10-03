import * as stylex from "@stylexjs/stylex";
import type { AnyFieldApi } from "@tanstack/react-form";
import { type ComponentProps, type ReactNode, useId } from "react";
import { colors } from "../../styles/tokens.stylex";
import { control } from "./controls";

// Labelled form controls. Each takes plain DOM props; TextField also binds a
// TanStack Form field and shows its first error.

function Field({
  label,
  hideLabel = false,
  hint,
  error,
  children,
}: {
  label: string;
  /** Keep the label for screen readers only, when something else on the page already names the control. */
  hideLabel?: boolean;
  hint?: string | undefined;
  error?: string | undefined;
  children: (ids: { id: string; describedBy: string | undefined }) => ReactNode;
}) {
  const id = useId();
  const hintId = hint ? `${id}-hint` : undefined;
  const errorId = error ? `${id}-error` : undefined;
  const describedBy = [hintId, errorId].filter(Boolean).join(" ") || undefined;
  return (
    <div {...stylex.props(styles.field)}>
      <label htmlFor={id} {...stylex.props(styles.label, hideLabel && styles.hidden)}>
        {label}
      </label>
      {children({ id, describedBy })}
      {hint ? (
        <span id={hintId} {...stylex.props(styles.hint)}>
          {hint}
        </span>
      ) : null}
      {error ? (
        <span id={errorId} {...stylex.props(styles.error)}>
          {error}
        </span>
      ) : null}
    </div>
  );
}

type Labelled = {
  label: string;
  hideLabel?: boolean;
  hint?: string | undefined;
  error?: string | undefined;
  /** Extra StyleX styles for the control itself, e.g. Geist Mono for quantities. */
  xstyle?: stylex.StyleXStyles;
};

export function Input({
  label,
  hideLabel,
  hint,
  error,
  xstyle,
  ...props
}: ComponentProps<"input"> & Labelled) {
  return (
    <Field label={label} hideLabel={hideLabel ?? false} hint={hint} error={error}>
      {({ id, describedBy }) => (
        <input
          id={id}
          aria-describedby={describedBy}
          aria-invalid={error ? true : undefined}
          {...props}
          {...stylex.props(control.field, error ? control.invalid : null, xstyle)}
        />
      )}
    </Field>
  );
}

export function Textarea({
  label,
  hint,
  error,
  xstyle,
  ...props
}: ComponentProps<"textarea"> & Labelled) {
  return (
    <Field label={label} hint={hint} error={error}>
      {({ id, describedBy }) => (
        <textarea
          id={id}
          aria-describedby={describedBy}
          aria-invalid={error ? true : undefined}
          {...props}
          {...stylex.props(control.field, control.textarea, error ? control.invalid : null, xstyle)}
        />
      )}
    </Field>
  );
}

export function Select({ label, hint, error, ...props }: ComponentProps<"select"> & Labelled) {
  return (
    <Field label={label} hint={hint} error={error}>
      {({ id, describedBy }) => (
        <select
          id={id}
          aria-describedby={describedBy}
          aria-invalid={error ? true : undefined}
          {...props}
          {...stylex.props(control.field, control.select, error ? control.invalid : null)}
        />
      )}
    </Field>
  );
}

const issueText = (issue: unknown) =>
  typeof issue === "string"
    ? issue
    : typeof issue === "object" && issue !== null && "message" in issue
      ? String(issue.message)
      : "";

/** An Input bound to a TanStack Form field. */
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
    <Input
      label={label}
      error={message}
      name={field.name}
      type={type}
      autoComplete={autoComplete}
      value={field.state.value as string}
      onBlur={field.handleBlur}
      onChange={(e) => field.handleChange(e.target.value)}
    />
  );
}

const styles = stylex.create({
  field: { display: "flex", flexDirection: "column", gap: 6 },
  label: { fontSize: 14, fontWeight: 500, color: colors.subtext },
  hidden: {
    position: "absolute",
    width: 1,
    height: 1,
    margin: -1,
    padding: 0,
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    whiteSpace: "nowrap",
    border: 0,
  },
  hint: { fontSize: 13, color: colors.subtext },
  error: { fontSize: 13, fontWeight: 500, color: colors.ink },
});
