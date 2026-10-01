import { copy } from "@cauldron/shared";
import { useEffect, useState } from "react";
import { currentTheme, type Theme, toggleTheme } from "../lib/theme";
import { IconButton } from "./ui";

export function ThemeToggle() {
  // Unknown until mounted: the server can't see the visitor's theme.
  const [theme, setTheme] = useState<Theme | null>(null);
  useEffect(() => setTheme(currentTheme()), []);
  const label = theme === "dark" ? copy.ui.switchToLight.text : copy.ui.switchToDark.text;
  return (
    <IconButton label={label} onClick={() => setTheme(toggleTheme())}>
      <span aria-hidden="true">{theme === "dark" ? "☀" : "☾"}</span>
    </IconButton>
  );
}
