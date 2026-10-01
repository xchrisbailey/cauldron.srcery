import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { type DragEvent, type KeyboardEvent, useRef, useState } from "react";
import { colors } from "../../styles/tokens.stylex";
import { focusRing } from "../ui/controls";

// Reordering for the ingredient and step lists: drag a row by its handle, or
// focus the handle and press the arrow keys. Moves are announced politely.

export function useReorder(count: number, move: (from: number, to: number) => void) {
  const dragFrom = useRef<number | null>(null);
  const [over, setOver] = useState<number | null>(null);
  const [announcement, setAnnouncement] = useState("");

  const moveTo = (from: number, to: number) => {
    if (to < 0 || to >= count || to === from) return;
    move(from, to);
    setAnnouncement(copy.editor.moved(to + 1, count).text);
  };

  const handleProps = (index: number) => ({
    draggable: true,
    onDragStart: (e: DragEvent) => {
      dragFrom.current = index;
      e.dataTransfer.effectAllowed = "move";
      // Firefox needs data set for a drag to start.
      e.dataTransfer.setData("text/plain", String(index));
    },
    onDragEnd: () => {
      dragFrom.current = null;
      setOver(null);
    },
    onKeyDown: (e: KeyboardEvent) => {
      if (e.key === "ArrowUp" || e.key === "ArrowDown") {
        e.preventDefault();
        // React moves the row's own node when it goes down, which drops focus.
        const handle = e.currentTarget as HTMLElement;
        moveTo(index, e.key === "ArrowUp" ? index - 1 : index + 1);
        requestAnimationFrame(() => handle.focus());
      }
    },
  });

  const rowProps = (index: number) => ({
    onDragOver: (e: DragEvent) => {
      if (dragFrom.current === null) return;
      e.preventDefault();
      setOver(index);
    },
    onDrop: (e: DragEvent) => {
      e.preventDefault();
      if (dragFrom.current !== null) moveTo(dragFrom.current, index);
      dragFrom.current = null;
      setOver(null);
    },
  });

  return { handleProps, rowProps, over, announcement, moveTo };
}

/** The grip a row is dragged by; a button so it can take focus and arrow keys. */
export function DragHandle({
  label,
  ...props
}: { label: string } & ReturnType<ReturnType<typeof useReorder>["handleProps"]>) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-description={copy.editor.moveHint.text}
      title={copy.editor.moveHint.text}
      {...props}
      {...stylex.props(styles.handle, focusRing.ring)}
    >
      <svg width="12" height="16" viewBox="0 0 12 16" aria-hidden="true">
        {[3, 8, 13].flatMap((y) => [
          <circle key={`a${y}`} cx="3.5" cy={y} r="1.4" fill="currentColor" />,
          <circle key={`b${y}`} cx="8.5" cy={y} r="1.4" fill="currentColor" />,
        ])}
      </svg>
    </button>
  );
}

export function Announcer({ message }: { message: string }) {
  return (
    <p aria-live="polite" {...stylex.props(styles.srOnly)}>
      {message}
    </p>
  );
}

const styles = stylex.create({
  handle: {
    display: "inline-grid",
    placeItems: "center",
    width: 28,
    height: 36,
    padding: 0,
    borderWidth: 0,
    borderRadius: 6,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.overlay1,
    cursor: { default: "grab", ":active": "grabbing" },
    flexShrink: 0,
  },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
