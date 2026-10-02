import { copy } from "@cauldron/shared";

/**
 * Head meta for a page: "<Page> · Cauldron". `page` is copy, or the cook's own
 * text such as a recipe title. Pass nothing for the bare app name.
 */
export const pageTitle = (page?: copy.CopyString | string) => {
  const name = typeof page === "string" ? page : page?.text;
  return { meta: [{ title: name ? `${name} · ${copy.ui.appName.text}` : copy.ui.appName.text }] };
};
