import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { Link } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { colors, fonts } from "../styles/tokens.stylex";
import { Lockup } from "./Lockup";
import { ThemeToggle } from "./ThemeToggle";
import { focusRing } from "./ui/controls";

/** The signed-out layout: lockup and theme toggle on top, content centered, the footer line below. */
export function PublicShell({ children }: { children: ReactNode }) {
  return (
    <div {...stylex.props(styles.page)}>
      <header {...stylex.props(styles.header)}>
        <Link
          to="/"
          aria-label={copy.ui.appName.text}
          {...stylex.props(styles.home, focusRing.ring)}
        >
          <Lockup />
        </Link>
        <ThemeToggle />
      </header>
      <main id="main" {...stylex.props(styles.main)}>
        {children}
      </main>
      <footer {...stylex.props(styles.footer)}>{copy.ui.footer.text}</footer>
    </div>
  );
}

const styles = stylex.create({
  page: { minHeight: "100dvh", display: "flex", flexDirection: "column" },
  header: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    paddingBlock: 14,
    paddingInline: { default: 16, "@media (min-width: 768px)": 28 },
  },
  home: { borderRadius: 8, color: colors.ink, textDecoration: "none" },
  main: {
    flex: 1,
    display: "grid",
    placeItems: "center",
    paddingBlock: 24,
    paddingInline: 16,
  },
  footer: {
    paddingBlock: 20,
    paddingInline: 16,
    textAlign: "center",
    fontFamily: fonts.mono,
    fontSize: 12,
    color: colors.subtext,
  },
});
