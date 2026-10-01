import { parseHTML } from "linkedom";

// Reading saved or fetched HTML: the document, text with entities decoded,
// the page's own metadata, and its readable text for the model.

export type HtmlDocument = ReturnType<typeof parseHTML>["document"];
type El = NonNullable<ReturnType<HtmlDocument["querySelector"]>>;

export const parseDocument = (html: string): HtmlDocument => parseHTML(html).document;

/** Text with HTML entities and tags removed, whitespace collapsed. */
export const plainText = (value: string): string => {
  if (!/[<&]/.test(value)) return value.replace(/\s+/g, " ").trim();
  const { document } = parseHTML(`<div>${value.replace(/<br\s*\/?>/gi, " ")}</div>`);
  return (document.querySelector("div")?.textContent ?? value).replace(/\s+/g, " ").trim();
};

const attr = (el: El | null | undefined, name: string) => el?.getAttribute(name)?.trim() || null;

const meta = (document: HtmlDocument, ...keys: ReadonlyArray<string>) => {
  for (const key of keys) {
    const el =
      document.querySelector(`meta[property="${key}"]`) ??
      document.querySelector(`meta[name="${key}"]`);
    const content = attr(el, "content");
    if (content) return plainText(content);
  }
  return null;
};

/** A link resolved against the page, http(s) only. */
export const absolute = (href: string | null | undefined, base: string): string | null => {
  if (!href) return null;
  try {
    const url = new URL(href.trim(), base);
    return url.protocol === "http:" || url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
};

const TRACKING = /^(?:utm_.*|fbclid|gclid|msclkid|mc_[ce]id|igshid|ref|_ga|_gl)$/i;

/** A link without tracking parameters (utm_*, fbclid and the like). */
export const withoutTracking = (href: string | null): string | null => {
  if (!href) return null;
  try {
    const url = new URL(href);
    const tracking = Array.from(url.searchParams.keys()).filter((key) => TRACKING.test(key));
    for (const key of tracking) url.searchParams.delete(key);
    return url.toString();
  } catch {
    return href;
  }
};

export interface PageMeta {
  readonly title: string | null;
  readonly description: string | null;
  readonly siteName: string | null;
  readonly author: string | null;
  readonly imageUrl: string | null;
  readonly canonicalUrl: string | null;
}

/** Open Graph, Twitter and plain meta tags, and the canonical link. */
export const pageMeta = (document: HtmlDocument, base: string): PageMeta => ({
  title:
    meta(document, "og:title", "twitter:title") ??
    (document.querySelector("title")?.textContent?.trim() || null),
  description: meta(document, "og:description", "description", "twitter:description"),
  siteName: meta(document, "og:site_name", "application-name"),
  author: meta(document, "author", "article:author"),
  imageUrl: absolute(meta(document, "og:image", "og:image:url", "twitter:image"), base),
  canonicalUrl: withoutTracking(
    absolute(
      attr(document.querySelector('link[rel="canonical"]'), "href") ?? meta(document, "og:url"),
      base,
    ),
  ),
});

const BLOCK = new Set([
  "P",
  "DIV",
  "LI",
  "UL",
  "OL",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
  "SECTION",
  "ARTICLE",
  "TR",
  "BR",
  "BLOCKQUOTE",
  "HEADER",
  "FIGCAPTION",
  "DT",
  "DD",
]);
const NOISE =
  "script, style, noscript, template, svg, iframe, nav, footer, aside, form, button, [aria-hidden='true'], .comments, #comments, .comment, .advertisement, .ad, [class*='newsletter'], [class*='related']";

/**
 * The page's readable text, one block per line: the article (or main) when
 * there is one, without scripts, navigation, footers and comments. Fed to the
 * model when a page has no structured recipe.
 */
export const readableText = (document: HtmlDocument, max: number): string => {
  const root =
    document.querySelector("article") ??
    document.querySelector("main") ??
    document.querySelector("[role='main']") ??
    document.body;
  if (!root) return "";
  for (const el of root.querySelectorAll(NOISE)) el.remove();
  const out: Array<string> = [];
  let line = "";
  const flush = () => {
    const text = line.replace(/\s+/g, " ").trim();
    if (text !== "") out.push(text);
    line = "";
  };
  // Walked with a stack, not recursion: a hostile page can nest far deeper
  // than the call stack goes.
  type Item = { readonly node: ChildNode | El; readonly closes?: boolean };
  const stack: Array<Item> = [{ node: root }];
  while (stack.length > 0) {
    const { node, closes } = stack.pop()!;
    if (closes) {
      flush();
      continue;
    }
    if (node.nodeType === 3) {
      line += node.textContent ?? "";
      continue;
    }
    if (node.nodeType !== 1) continue;
    const el = node as El;
    const block = BLOCK.has(el.tagName);
    if (block) {
      flush();
      stack.push({ node, closes: true });
    }
    if (el.tagName === "LI") line += "- ";
    const children = [...el.childNodes];
    for (let i = children.length - 1; i >= 0; i--) stack.push({ node: children[i]! });
  }
  flush();
  return out.join("\n").slice(0, max);
};

/** The charset a response or page declares, defaulting to UTF-8. */
export const decodeHtml = (bytes: Uint8Array, contentType: string | null): string => {
  const declared = /charset=["']?([\w-]+)/i.exec(contentType ?? "")?.[1];
  const sniff = declared
    ? null
    : /<meta[^>]+charset=["']?([\w-]+)/i.exec(
        new TextDecoder("latin1").decode(bytes.slice(0, 2048)),
      )?.[1];
  const charset = declared ?? sniff ?? "utf-8";
  try {
    return new TextDecoder(charset).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
};
