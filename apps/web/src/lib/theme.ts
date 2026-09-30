// The theme toggle from srcery.computer: no choice follows the system; a
// choice is kept in localStorage and set as data-theme on <html>.

export type Theme = "light" | "dark";
const KEY = "theme";

/** Runs in <head> before first paint so a pinned theme never flashes the other one. */
export const themeScript = `(()=>{try{const t=localStorage.getItem("${KEY}");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch{}})()`;

export const currentTheme = (): Theme => {
  const pinned = document.documentElement.dataset.theme;
  if (pinned === "light" || pinned === "dark") return pinned;
  return matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
};

/** Pins the opposite of what's showing; pinning the system's own theme clears the pin. */
export const toggleTheme = (): Theme => {
  const next: Theme = currentTheme() === "dark" ? "light" : "dark";
  const system: Theme = matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  try {
    if (next === system) {
      localStorage.removeItem(KEY);
      document.documentElement.removeAttribute("data-theme");
    } else {
      localStorage.setItem(KEY, next);
      document.documentElement.dataset.theme = next;
    }
  } catch {
    document.documentElement.dataset.theme = next;
  }
  return next;
};
