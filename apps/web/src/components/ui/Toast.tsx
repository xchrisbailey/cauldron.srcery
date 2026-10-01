import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { colors } from "../../styles/tokens.stylex";
import { Button, IconButton } from "./Button";

// Short-lived notes in the corner ("Set", "Couldn't save"). The region is
// always in the page so screen readers announce what lands in it.

type Tone = "info" | "error";
/** A button in the toast, such as Undo. Pressing it also dismisses the toast. */
export interface ToastAction {
  readonly label: string;
  readonly onClick: () => void;
}

interface Toast {
  readonly id: number;
  readonly message: string;
  readonly tone: Tone;
  readonly action: ToastAction | undefined;
}

const ToastContext = createContext<(message: string, tone?: Tone, action?: ToastAction) => void>(
  () => {},
);

/** Shows a toast: `useToast()("Set")`, or with an action: `toast("Banished", "info", { label: "Undo", onClick })`. */
export const useToast = () => useContext(ToastContext);

const LIFETIME_MS = 5000;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ReadonlyArray<Toast>>([]);
  const next = useRef(0);
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>());
  useEffect(() => {
    const pending = timers.current;
    return () => pending.forEach(clearTimeout);
  }, []);
  const dismiss = useCallback((id: number) => {
    clearTimeout(timers.current.get(id));
    timers.current.delete(id);
    setToasts((all) => all.filter((t) => t.id !== id));
  }, []);
  const show = useCallback(
    (message: string, tone: Tone = "info", action?: ToastAction) => {
      const id = next.current++;
      setToasts((all) => [...all, { id, message, tone, action }]);
      // Errors and toasts with an action (Undo) stay until dismissed, so
      // there's time to read them and reach the button from the keyboard.
      if (tone === "info" && !action)
        timers.current.set(
          id,
          setTimeout(() => dismiss(id), LIFETIME_MS),
        );
    },
    [dismiss],
  );
  return (
    <ToastContext.Provider value={show}>
      {children}
      <div role="status" aria-live="polite" data-print="hide" {...stylex.props(styles.region)}>
        {toasts.map((t) => (
          <div key={t.id} {...stylex.props(styles.toast, t.tone === "error" && styles.error)}>
            <span {...stylex.props(styles.message)}>{t.message}</span>
            {t.action ? (
              <Button
                variant="secondary"
                onClick={() => {
                  dismiss(t.id);
                  t.action?.onClick();
                }}
              >
                {t.action.label}
              </Button>
            ) : null}
            <IconButton label={copy.ui.close.text} onClick={() => dismiss(t.id)}>
              ×
            </IconButton>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

const styles = stylex.create({
  region: {
    position: "fixed",
    insetInline: 16,
    bottom: 16,
    zIndex: 10,
    display: "flex",
    flexDirection: "column",
    alignItems: { default: "center", "@media (min-width: 768px)": "flex-end" },
    gap: 8,
    pointerEvents: "none",
  },
  toast: {
    pointerEvents: "auto",
    display: "flex",
    alignItems: "center",
    gap: 8,
    maxWidth: 420,
    paddingBlock: 6,
    paddingInlineStart: 14,
    paddingInlineEnd: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface1,
    backgroundColor: colors.crust,
    color: colors.ink,
    fontSize: 14,
    boxShadow: `0 12px 24px -12px ${colors.crust}`,
  },
  error: { borderColor: colors.heat },
  message: { flex: 1 },
});
