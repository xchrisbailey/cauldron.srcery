import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { type ReactNode, useEffect, useId, useRef } from "react";
import { colors } from "../../styles/tokens.stylex";
import { IconButton } from "./Button";

// Modal surfaces on the native <dialog>, which brings the focus trap, Escape to
// close, inert background and focus return for free. Every close goes
// through the native close event, so `onClose` runs once per close. Mark the element that
// should take focus on open with `data-autofocus`. Both are controlled:
// the parent owns `open` and hears about every close through `onClose`.

interface ModalProps {
  open: boolean;
  onClose: () => void;
  /** Shown as the heading and used as the accessible name. */
  title: string;
  /** Hide the heading visually but keep it as the accessible name. */
  hideTitle?: boolean;
  children: ReactNode;
}

function Modal({
  open,
  onClose,
  title,
  hideTitle,
  children,
  surface,
}: ModalProps & { surface: "dialog" | "sheet" }) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      dialog.showModal();
      dialog.querySelector<HTMLElement>("[data-autofocus]")?.focus();
    }
    if (!open && dialog.open) dialog.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onClose={onClose}
      // A click on the dialog element itself is a click on the backdrop.
      onClick={(e) => e.target === e.currentTarget && ref.current?.close()}
      {...stylex.props(styles.dialog, surface === "sheet" ? styles.sheet : styles.centered)}
    >
      <div {...stylex.props(styles.inner, surface === "sheet" && styles.innerSheet)}>
        <div {...stylex.props(styles.head, surface === "sheet" && styles.headSheet)}>
          <h2 id={titleId} {...stylex.props(styles.title, hideTitle && styles.srOnly)}>
            {title}
          </h2>
          <span {...stylex.props(styles.close)}>
            <IconButton label={copy.ui.close.text} onClick={() => ref.current?.close()}>
              <CloseGlyph />
            </IconButton>
          </span>
        </div>
        {children}
      </div>
    </dialog>
  );
}

/** A centered modal dialog. */
export function Dialog(props: ModalProps) {
  return <Modal {...props} surface="dialog" />;
}

/** A panel that slides in from the left edge; the phone menu. */
export function Sheet(props: ModalProps) {
  return <Modal {...props} surface="sheet" />;
}

function CloseGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
      <path
        d="M4 4l8 8M12 4l-8 8"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}

const enter = stylex.keyframes({
  from: { opacity: 0, transform: "translateY(8px)" },
  to: { opacity: 1, transform: "none" },
});
const slideIn = stylex.keyframes({
  from: { transform: "translateX(-100%)" },
  to: { transform: "none" },
});

const styles = stylex.create({
  dialog: {
    padding: 0,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    backgroundColor: colors.mantle,
    color: colors.ink,
    "::backdrop": { backgroundColor: `color-mix(in srgb, ${colors.crust} 65%, transparent)` },
  },
  centered: {
    width: "min(520px, calc(100vw - 32px))",
    maxHeight: "calc(100dvh - 64px)",
    marginTop: "12vh",
    borderRadius: 14,
    animationName: { default: enter, "@media (prefers-reduced-motion: reduce)": "none" },
    animationDuration: "160ms",
    animationTimingFunction: "ease-out",
  },
  sheet: {
    width: "min(300px, 85vw)",
    height: "100dvh",
    maxHeight: "100dvh",
    margin: 0,
    borderRadius: 0,
    borderTopWidth: 0,
    borderBottomWidth: 0,
    borderLeftWidth: 0,
    animationName: { default: slideIn, "@media (prefers-reduced-motion: reduce)": "none" },
    animationDuration: "200ms",
    animationTimingFunction: "ease-out",
  },
  inner: { display: "flex", flexDirection: "column", gap: 16, padding: 16, height: "100%" },
  // The sheet's content (the sidebar) brings its own padding.
  innerSheet: { padding: 0, gap: 0 },
  headSheet: { paddingTop: 12, paddingInline: 12 },
  head: { display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 },
  title: { margin: 0, fontSize: 17, fontWeight: 650 },
  // Stays on the right even when the title is visually hidden.
  close: { marginInlineStart: "auto" },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
