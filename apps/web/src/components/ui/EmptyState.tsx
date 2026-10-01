import * as stylex from "@stylexjs/stylex";
import type { ReactNode } from "react";
import { colors } from "../../styles/tokens.stylex";
import { Mark } from "../Mark";

/** What a page shows when it has nothing yet: the mark, a line of copy and what to do next. */
export function EmptyState({ message, actions }: { message: string; actions?: ReactNode }) {
  return (
    <div {...stylex.props(styles.box)}>
      <Mark size={56} />
      <p {...stylex.props(styles.message)}>{message}</p>
      {actions ? <div {...stylex.props(styles.actions)}>{actions}</div> : null}
    </div>
  );
}

const styles = stylex.create({
  box: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 16,
    paddingBlock: 48,
    paddingInline: 20,
    borderRadius: 14,
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: colors.surface1,
    textAlign: "center",
  },
  message: { margin: 0, maxWidth: "40ch", color: colors.subtext, textWrap: "balance" },
  actions: { display: "flex", flexWrap: "wrap", justifyContent: "center", gap: 8 },
});
