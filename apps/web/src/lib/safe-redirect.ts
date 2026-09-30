const BASE = "http://x";

/**
 * Only same-site paths, so a crafted link can't bounce people to another site.
 * Resolves the target against a dummy origin the way a browser would, so
 * backslashes, tabs and other tricks that change the origin are caught; keeps
 * only path, search and hash.
 */
export const safeRedirect = (to: string | undefined): string => {
  if (!to || !to.startsWith("/")) return "/";
  // Browsers strip tabs and newlines from URLs, and control characters have no place in a path.
  // oxlint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(to)) return "/";
  let url: URL;
  try {
    url = new URL(to, BASE);
  } catch {
    return "/";
  }
  if (url.origin !== BASE) return "/";
  return url.pathname + url.search + url.hash;
};
