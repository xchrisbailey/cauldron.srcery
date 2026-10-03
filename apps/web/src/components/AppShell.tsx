import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { formatForDisplay, useHotkey } from "@tanstack/react-hotkeys";
import { Link, useRouterState } from "@tanstack/react-router";
import { type ReactNode, useEffect, useState } from "react";
import { colors, fonts, type } from "../styles/tokens.stylex";
import {
  BagGlyph,
  BookGlyph,
  CalendarGlyph,
  ChartGlyph,
  MenuGlyph,
  PersonGlyph,
  PlusGlyph,
  SearchGlyph,
} from "./glyphs";
import { Lockup } from "./Lockup";
import { SummonDialog } from "./SummonDialog";
import { ThemeToggle } from "./ThemeToggle";
import { focusRing } from "./ui/controls";
import { IconButton, Sheet } from "./ui";

// The signed-in layout from the brand book: lockup, search and nav in a
// sidebar on the left, content on the right. Below 768px the sidebar folds
// into a top bar and a sheet menu.

const nav = [
  { to: "/recipes", label: copy.nav.recipes.text, Glyph: BookGlyph },
  { to: "/week", label: copy.nav.week.text, Glyph: CalendarGlyph },
  { to: "/gather", label: copy.nav.gather.text, Glyph: BagGlyph },
  { to: "/tracker", label: copy.nav.tracker.text, Glyph: ChartGlyph },
] as const;

export function AppShell({ children }: { children: ReactNode }) {
  const [summoning, setSummoning] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  // Following a link in the sheet closes it.
  useEffect(() => setMenuOpen(false), [pathname]);
  // So does widening the window past the phone layout.
  useEffect(() => {
    const wide = matchMedia("(min-width: 768px)");
    const close = () => wide.matches && setMenuOpen(false);
    wide.addEventListener("change", close);
    return () => wide.removeEventListener("change", close);
  }, []);
  useHotkey("Mod+K", () => {
    setMenuOpen(false);
    setSummoning((open) => !open);
  });
  const summon = () => {
    setMenuOpen(false);
    setSummoning(true);
  };

  return (
    <div data-print="single" {...stylex.props(styles.app)}>
      <a href="#main" {...stylex.props(styles.skip, focusRing.ring)}>
        {copy.ui.skipToContent.text}
      </a>
      <aside data-print="hide" {...stylex.props(styles.sidebar)}>
        <Sidebar pathname={pathname} onSummon={summon} />
      </aside>
      <header data-print="hide" {...stylex.props(styles.topbar)}>
        <Link to="/recipes" aria-label={copy.ui.appName.text} {...stylex.props(focusRing.ring)}>
          <Lockup />
        </Link>
        <div {...stylex.props(styles.topActions)}>
          <IconButton label={copy.recipes.summon.text} onClick={summon}>
            <SearchGlyph />
          </IconButton>
          <IconButton
            label={copy.ui.menu.text}
            aria-haspopup="dialog"
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen(true)}
          >
            <MenuGlyph />
          </IconButton>
        </div>
      </header>
      <Sheet open={menuOpen} onClose={() => setMenuOpen(false)} title={copy.ui.menu.text} hideTitle>
        <Sidebar pathname={pathname} onSummon={summon} />
      </Sheet>
      <main id="main" tabIndex={-1} {...stylex.props(styles.main)}>
        {children}
      </main>
      <SummonDialog open={summoning} onClose={() => setSummoning(false)} />
    </div>
  );
}

function Sidebar({ pathname, onSummon }: { pathname: string; onSummon: () => void }) {
  // The platform's own shortcut label (⌘K or Ctrl+K), known only in the browser.
  const [shortcut, setShortcut] = useState("⌘K");
  useEffect(() => setShortcut(formatForDisplay("Mod+K").replace(/\s/g, "")), []);
  return (
    <div {...stylex.props(styles.sideInner)}>
      <Link
        to="/recipes"
        aria-label={copy.ui.appName.text}
        {...stylex.props(styles.brand, focusRing.ring)}
      >
        <Lockup />
      </Link>
      <button type="button" onClick={onSummon} {...stylex.props(styles.search, focusRing.ring)}>
        <SearchGlyph />
        <span>{copy.recipes.summon.text}</span>
        <kbd {...stylex.props(styles.kbd)}>{shortcut}</kbd>
      </button>
      <nav aria-label={copy.ui.mainNav.text}>
        <ul {...stylex.props(styles.list)}>
          {nav.map(({ to, label, Glyph }) => {
            const active = pathname === to || pathname.startsWith(`${to}/`);
            return (
              <li key={to}>
                <Link
                  to={to}
                  {...stylex.props(styles.item, active && styles.itemActive, focusRing.ring)}
                >
                  <span {...stylex.props(styles.glyph, active && styles.glyphActive)}>
                    <Glyph />
                  </span>
                  {label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
      <Link
        to="/account"
        {...stylex.props(
          styles.item,
          styles.account,
          pathname === "/account" && styles.itemActive,
          focusRing.ring,
        )}
      >
        <span {...stylex.props(styles.glyph, pathname === "/account" && styles.glyphActive)}>
          <PersonGlyph />
        </span>
        {copy.auth.account.text}
      </Link>
      <div {...stylex.props(styles.foot)}>
        <Link to="/recipes/new" {...stylex.props(styles.conjure, focusRing.ring)}>
          <PlusGlyph />
          {copy.recipes.conjure.text}
        </Link>
        <ThemeToggle />
      </div>
    </div>
  );
}

// Don't add "@media print" next to this in a StyleX value: StyleX rewrites
// the set into "(min-width) and (not (print))", which never matches, and the
// desktop layout is lost. Print rules live in app.css on data-print.
const desktop = "@media (min-width: 768px)";
const SIDEBAR = 216;

const styles = stylex.create({
  app: {
    minHeight: "100dvh",
    display: "grid",
    gridTemplateColumns: {
      default: "minmax(0, 1fr)",
      [desktop]: `${SIDEBAR}px minmax(0, 1fr)`,
    },
    gridTemplateRows: { default: "auto 1fr", [desktop]: "1fr" },
  },
  skip: {
    position: "absolute",
    left: 8,
    top: { default: -48, ":focus": 8 },
    zIndex: 20,
    paddingBlock: 8,
    paddingInline: 12,
    borderRadius: 8,
    backgroundColor: colors.magic,
    color: colors.base,
    fontWeight: 600,
    textDecoration: "none",
  },
  sidebar: {
    display: { default: "none", [desktop]: "block" },
    position: "sticky",
    top: 0,
    height: "100dvh",
    backgroundColor: colors.mantle,
    borderRightWidth: 1,
    borderRightStyle: "solid",
    borderRightColor: colors.surface0,
  },
  sideInner: {
    height: "100%",
    display: "flex",
    flexDirection: "column",
    gap: 18,
    paddingTop: 20,
    paddingInline: 14,
    paddingBottom: 14,
  },
  brand: {
    alignSelf: "flex-start",
    paddingInline: 6,
    borderRadius: 8,
    color: colors.ink,
    textDecoration: "none",
  },
  search: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    width: "100%",
    paddingBlock: 7,
    paddingInline: 10,
    borderRadius: 8,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: "transparent", ":hover": colors.surface1 },
    backgroundColor: colors.crust,
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 13,
    textAlign: "start",
    cursor: "pointer",
  },
  kbd: { marginInlineStart: "auto", fontFamily: fonts.mono, fontSize: 11, color: colors.subtext },
  list: { listStyle: "none", margin: 0, padding: 0, display: "grid", gap: 2 },
  item: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    minHeight: 36,
    paddingBlock: 7,
    paddingInline: 10,
    borderRadius: 8,
    color: colors.ink,
    fontSize: type.controlSize,
    fontWeight: type.controlWeight,
    textDecoration: "none",
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
  },
  itemActive: {
    backgroundColor: {
      default: `color-mix(in srgb, ${colors.magic} 18%, transparent)`,
      ":hover": `color-mix(in srgb, ${colors.magic} 24%, transparent)`,
    },
  },
  glyph: { display: "inline-flex", color: colors.subtext },
  glyphActive: { color: colors.magic },
  foot: {
    display: "flex",
    alignItems: "center",
    gap: 4,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: colors.surface0,
  },
  conjure: {
    flex: 1,
    display: "flex",
    alignItems: "center",
    gap: 6,
    minHeight: 36,
    paddingInline: 8,
    borderRadius: 8,
    color: colors.ink,
    fontSize: 13,
    fontWeight: 500,
    whiteSpace: "nowrap",
    textDecoration: "none",
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
  },
  // Pushes the account link and the footer to the bottom of the sidebar.
  account: { marginTop: "auto" },
  topbar: {
    display: { default: "flex", [desktop]: "none" },
    alignItems: "center",
    justifyContent: "space-between",
    gap: 12,
    position: "sticky",
    top: 0,
    zIndex: 5,
    paddingBlock: 10,
    paddingInline: 16,
    backgroundColor: colors.mantle,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
  },
  topActions: { display: "flex", gap: 4 },
  main: {
    minWidth: 0,
    display: "flex",
    flexDirection: "column",
    gap: 24,
    paddingBlock: { default: 20, [desktop]: 28 },
    paddingInline: { default: 16, [desktop]: 40 },
    outline: "none",
  },
});
