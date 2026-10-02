import * as stylex from "@stylexjs/stylex";
import { copy, type RecipeSort, type RecipeSummary } from "@cauldron/shared";
import { useDebouncer } from "@tanstack/react-pacer";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useWindowVirtualizer } from "@tanstack/react-virtual";
import { Schema } from "effect";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { RecipeCard, RecipeRow } from "../../../components/RecipeCard";
import {
  Button,
  ButtonLink,
  EmptyState,
  FormMessage,
  PageHeader,
  Skeleton,
} from "../../../components/ui";
import { control } from "../../../components/ui/controls";
import { usePreference } from "../../../lib/preference";
import { libraryQuery, tagsQuery } from "../../../lib/recipes";
import { SearchFlag } from "../../../lib/search";
import { colors, fonts } from "../../../styles/tokens.stylex";
import { pageTitle } from "../../../lib/page-title";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({
    verified: SearchFlag,
    error: Schema.optional(Schema.String),
    q: Schema.optional(Schema.String),
    tag: Schema.optional(Schema.String),
    sort: Schema.optional(Schema.Literals(["recent", "title", "lastCooked"])),
  }),
);

export const Route = createFileRoute("/_authed/recipes/")({
  head: () => pageTitle(copy.nav.recipes),
  validateSearch: Search,
  // Recipes are fetched with the visitor's cookie, which only the browser sends.
  ssr: false,
  loaderDeps: ({ search }) => ({
    q: search.q ?? "",
    tag: search.tag,
    sort: search.sort ?? "recent",
  }),
  // Start fetching on hover and as the page opens, without holding up a
  // search as you type: the page keeps showing the last results meanwhile.
  loader: ({ context, deps }) => {
    void context.queryClient.prefetchInfiniteQuery(libraryQuery(deps));
    void context.queryClient.prefetchQuery(tagsQuery());
  },
  component: Recipes,
});

type View = "grid" | "list";
const CARD_MIN = 220;
const GAP = 16;

const decodeView = (raw: string | null): View => (raw === "list" ? "list" : "grid");

/** Grid or list is a per-viewer preference, remembered in this browser. */
function useView() {
  const [view, setView] = usePreference("cauldron:library-view", decodeView, "grid");
  return [view, setView] as const;
}

function Recipes() {
  const search = Route.useSearch();
  const navigate = useNavigate({ from: Route.fullPath });
  const [view, setView] = useView();
  const filters = Route.useLoaderDeps();
  const sort: RecipeSort = filters.sort;
  const filtered = Boolean(search.q || search.tag);

  // The field updates as you type; the URL (and the query) follow, debounced.
  const urlQ = search.q ?? "";
  const [text, setText] = useState(urlQ);
  // The last q this page put in the URL, to tell our own update from another one.
  const [sent, setSent] = useState(urlQ);
  const [seen, setSeen] = useState(urlQ);
  const searchFor = useDebouncer(
    (value: string) => {
      const q = value.trim();
      setSent(q);
      void navigate({ search: (prev) => ({ ...prev, q: q || undefined }), replace: true });
    },
    { wait: 200 },
  );
  // The field follows the URL when it changes on its own (the Recipes link,
  // back and forward), adjusted during render rather than in an effect. A
  // search still waiting to go out would undo that, so it's dropped.
  if (urlQ !== seen) {
    setSeen(urlQ);
    if (urlQ !== sent) {
      searchFor.cancel();
      setSent(urlQ);
      setText(urlQ);
    }
  }

  const tags = useQuery(tagsQuery());
  const library = useInfiniteQuery({
    ...libraryQuery(filters),
    placeholderData: (previous) => previous,
  });
  const recipes = library.data?.pages.flatMap((page) => page.items) ?? [];

  const setFilter = (next: { tag?: string | undefined; sort?: RecipeSort }) =>
    void navigate({ search: (prev) => ({ ...prev, ...next }), replace: true });

  const conjure = (
    <>
      <ButtonLink to="/recipes/distill" variant="secondary">
        {copy.recipes.distillFromLink.text}
      </ButtonLink>
      <ButtonLink to="/recipes/new">{copy.recipes.conjure.text}</ButtonLink>
    </>
  );

  return (
    <>
      <PageHeader title={copy.nav.recipes.text} actions={conjure} />
      {search.error ? (
        <FormMessage tone="error">{copy.auth.linkExpired.text}</FormMessage>
      ) : search.verified ? (
        <FormMessage tone="info">{copy.auth.emailVerified.text}</FormMessage>
      ) : null}

      <div role="search" {...stylex.props(styles.toolbar)}>
        <label {...stylex.props(styles.searchField)}>
          <span {...stylex.props(styles.srOnly)}>{copy.library.search.text}</span>
          <input
            type="search"
            value={text}
            placeholder={copy.library.searchPlaceholder.text}
            onChange={(e) => {
              setText(e.target.value);
              searchFor.maybeExecute(e.target.value);
            }}
            autoComplete="off"
            {...stylex.props(control.field)}
          />
        </label>
        <label {...stylex.props(styles.select)}>
          <span {...stylex.props(styles.srOnly)}>{copy.library.tag.text}</span>
          <select
            value={search.tag ?? ""}
            onChange={(e) => setFilter({ tag: e.target.value || undefined })}
            {...stylex.props(control.field, control.select)}
          >
            <option value="">{copy.library.allTags.text}</option>
            {(tags.data ?? [])
              .filter((tag) => tag.recipeCount > 0 || tag.id === search.tag)
              .map((tag) => (
                <option key={tag.id} value={tag.id}>
                  {copy.library.tagOption(tag.name, tag.recipeCount).text}
                </option>
              ))}
          </select>
        </label>
        <label {...stylex.props(styles.select)}>
          <span {...stylex.props(styles.srOnly)}>{copy.library.sort.text}</span>
          <select
            value={sort}
            onChange={(e) => setFilter({ sort: e.target.value as RecipeSort })}
            {...stylex.props(control.field, control.select)}
          >
            <option value="recent">{copy.library.sortRecent.text}</option>
            <option value="title">{copy.library.sortTitle.text}</option>
            <option value="lastCooked">{copy.library.sortLastCooked.text}</option>
          </select>
        </label>
        <div role="group" aria-label={copy.library.view.text} {...stylex.props(styles.views)}>
          {(["grid", "list"] as const).map((choice) => (
            <button
              key={choice}
              type="button"
              aria-pressed={view === choice}
              onClick={() => setView(choice)}
              {...stylex.props(styles.viewButton, view === choice && styles.viewOn)}
            >
              {copy.library[choice].text}
            </button>
          ))}
        </div>
      </div>

      {library.isPending ? (
        <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.skeletons)}>
          {Array.from({ length: 6 }, (_, i) => (
            <Skeleton key={i} height={220} />
          ))}
        </div>
      ) : library.isError && !library.data ? (
        <FormMessage tone="error">{copy.errors.internal.text}</FormMessage>
      ) : recipes.length === 0 ? (
        filtered ? (
          <EmptyState
            message={copy.library.noMatches.text}
            actions={
              <Button
                variant="secondary"
                onClick={() => {
                  searchFor.cancel();
                  setText("");
                  setSent("");
                  void navigate({
                    search: (prev) => ({ ...prev, q: undefined, tag: undefined }),
                    replace: true,
                  });
                }}
              >
                {copy.library.clearFilters.text}
              </Button>
            }
          />
        ) : (
          <EmptyState message={copy.recipes.empty.text} actions={conjure} />
        )
      ) : (
        <Results
          recipes={recipes}
          view={view}
          hasMore={library.hasNextPage}
          loadMore={() => {
            // Never cancel a refetch in flight, and stop after a failed page.
            if (!library.isFetching && !library.isFetchNextPageError) {
              void library.fetchNextPage({ cancelRefetch: false });
            }
          }}
          loadingMore={library.isFetchingNextPage}
          stale={library.isPlaceholderData}
        />
      )}
      {library.isFetchNextPageError ? (
        <div {...stylex.props(styles.retry)}>
          <FormMessage tone="error">{copy.library.couldntLoadMore.text}</FormMessage>
          <Button variant="secondary" onClick={() => void library.fetchNextPage()}>
            {copy.library.retry.text}
          </Button>
        </div>
      ) : null}
    </>
  );
}

/**
 * The results, virtualized against the window: only the rows on screen are
 * in the DOM, and the next page loads as the last row comes into view.
 */
function Results({
  recipes,
  view,
  hasMore,
  loadMore,
  loadingMore,
  stale,
}: {
  recipes: ReadonlyArray<RecipeSummary>;
  view: View;
  hasMore: boolean;
  loadMore: () => void;
  loadingMore: boolean;
  /** Showing the previous filter's results while the new ones load. */
  stale: boolean;
}) {
  const container = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [offset, setOffset] = useState(0);

  useLayoutEffect(() => {
    const element = container.current;
    if (!element) return;
    const measure = () => {
      setWidth(element.clientWidth);
      setOffset(element.getBoundingClientRect().top + window.scrollY);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const columns = view === "list" ? 1 : Math.max(1, Math.floor((width + GAP) / (CARD_MIN + GAP)));
  const rows = Math.ceil(recipes.length / columns);
  const virtualizer = useWindowVirtualizer({
    count: rows,
    estimateSize: () => (view === "list" ? 53 : 300),
    overscan: 4,
    scrollMargin: offset,
    gap: view === "list" ? 0 : GAP,
  });
  const items = virtualizer.getVirtualItems();
  // Rows change height with the view and the column count: measure again.
  useEffect(() => virtualizer.measure(), [view, columns]);
  const last = items[items.length - 1];

  useEffect(() => {
    if (last && last.index >= rows - 2 && hasMore) loadMore();
  }, [last?.index, rows, hasMore]);

  return (
    <div ref={container} aria-busy={loadingMore || stale} {...stylex.props(stale && styles.stale)}>
      <p {...stylex.props(styles.srOnly)} aria-live="polite">
        {copy.library.count(recipes.length).text}
      </p>
      <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
        {items.map((row) => (
          <div
            key={row.key}
            data-index={row.index}
            ref={virtualizer.measureElement}
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              width: "100%",
              transform: `translateY(${row.start - virtualizer.options.scrollMargin}px)`,
            }}
            {...stylex.props(view === "grid" ? styles.gridRow : null)}
          >
            {recipes
              .slice(row.index * columns, row.index * columns + columns)
              .map((recipe) =>
                view === "grid" ? (
                  <RecipeCard key={recipe.id} recipe={recipe} />
                ) : (
                  <RecipeRow key={recipe.id} recipe={recipe} />
                ),
              )}
          </div>
        ))}
      </div>
      {loadingMore ? (
        <p role="status" {...stylex.props(styles.more)}>
          {copy.library.loadingMore.text}
        </p>
      ) : null}
    </div>
  );
}

const styles = stylex.create({
  toolbar: {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    gap: 8,
  },
  searchField: { flex: "1 1 240px", minWidth: 0 },
  select: { flex: "0 1 180px", minWidth: 120 },
  views: {
    display: "inline-flex",
    padding: 2,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: colors.surface0,
    borderRadius: 10,
  },
  viewButton: {
    minHeight: 36,
    paddingInline: 12,
    borderWidth: 0,
    borderRadius: 8,
    backgroundColor: { default: "transparent", ":hover": colors.surface0 },
    color: colors.subtext,
    fontSize: 13.5,
    cursor: "pointer",
    outline: { default: "none", ":focus-visible": `2px solid ${colors.magic}` },
  },
  viewOn: { backgroundColor: colors.surface0, color: colors.ink, fontWeight: 600 },
  skeletons: {
    display: "grid",
    gridTemplateColumns: `repeat(auto-fill, minmax(${CARD_MIN}px, 1fr))`,
    gap: GAP,
  },
  gridRow: {
    display: "grid",
    gridTemplateColumns: `repeat(auto-fill, minmax(${CARD_MIN}px, 1fr))`,
    gap: GAP,
  },
  retry: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12 },
  stale: { opacity: 0.6 },
  more: { textAlign: "center", fontFamily: fonts.mono, fontSize: 12.5, color: colors.subtext },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
});
