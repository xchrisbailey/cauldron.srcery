import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { useEffect, useState } from "react";
import { currentTheme, type Theme, toggleTheme } from "../lib/theme";
import { colors, fonts } from "../styles/tokens.stylex";

export function ThemeToggle() {
  // Unknown until mounted: the server can't see the visitor's theme.
  const [theme, setTheme] = useState<Theme | null>(null);
  useEffect(() => setTheme(currentTheme()), []);
  const label = theme === "dark" ? copy.ui.switchToLight.text : copy.ui.switchToDark.text;
  return (
    <button
      type="button"
      {...stylex.props(styles.button)}
      onClick={() => setTheme(toggleTheme())}
      aria-label={label}
      title={label}
    >
      {theme === "dark" ? "☀" : "☾"}
    </button>
  );
}

const styles = stylex.create({
  button: {
    width: 32,
    height: 32,
    borderRadius: 8,
    borderWidth: 0,
    cursor: "pointer",
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontFamily: fonts.ui,
    fontSize: 16,
  },
});
