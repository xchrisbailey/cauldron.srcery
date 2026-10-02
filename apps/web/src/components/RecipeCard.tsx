import * as stylex from "@stylexjs/stylex";
import {
  formatTimer,
  macroLine,
  photoUrl,
  recipeMinutes,
  type RecipeSummary,
  type Tag,
} from "@cauldron/shared";
import { Link } from "@tanstack/react-router";
import { colors, fonts } from "../styles/tokens.stylex";
import { Mark } from "./Mark";
import { focusRing } from "./ui/controls";

// A recipe in the library: a card in the grid, or a row in the compact list.

export function RecipeCard({ recipe }: { recipe: RecipeSummary }) {
  const minutes = recipeMinutes(recipe);
  const macros = macroLine(recipe.macros);
  return (
    <Link
      to="/recipes/$id"
      params={{ id: recipe.id }}
      {...stylex.props(styles.card, focusRing.ring)}
    >
      <div {...stylex.props(styles.photo)}>
        {recipe.photoKey ? (
          // Decorative here: the card's title names the recipe.
          <img
            src={photoUrl(recipe.photoKey, "card")}
            alt=""
            loading="lazy"
            decoding="async"
            {...stylex.props(styles.image)}
          />
        ) : (
          <span aria-hidden="true">
            <Mark size={44} />
          </span>
        )}
      </div>
      <div {...stylex.props(styles.body)}>
        <h2 {...stylex.props(styles.title)}>{recipe.title}</h2>
        <div {...stylex.props(styles.meta)}>
          {minutes !== null && minutes > 0 ? (
            <span {...stylex.props(styles.time)}>{formatTimer(minutes * 60)}</span>
          ) : null}
          {recipe.tags.slice(0, 2).map((tag) => (
            <TagPill key={tag.id} tag={tag} />
          ))}
        </div>
        {macros ? (
          <p {...stylex.props(styles.macros)}>
            <span aria-hidden="true">{macros.text}</span>
            <span {...stylex.props(styles.srOnly)}>{macros.label}</span>
          </p>
        ) : null}
      </div>
    </Link>
  );
}

export function RecipeRow({ recipe }: { recipe: RecipeSummary }) {
  const minutes = recipeMinutes(recipe);
  return (
    <Link
      to="/recipes/$id"
      params={{ id: recipe.id }}
      {...stylex.props(styles.row, focusRing.ring)}
    >
      <span {...stylex.props(styles.rowTitle)}>{recipe.title}</span>
      <span {...stylex.props(styles.rowTags)}>
        {recipe.tags.slice(0, 3).map((tag) => (
          <TagPill key={tag.id} tag={tag} />
        ))}
      </span>
      <span {...stylex.props(styles.time, styles.rowTime)}>
        {minutes !== null && minutes > 0 ? formatTimer(minutes * 60) : ""}
      </span>
    </Link>
  );
}

function TagPill({ tag }: { tag: Tag }) {
  return (
    <span
      {...stylex.props(
        styles.tag,
        tag.kind === "meal" && styles.tagMeal,
        tag.kind === "diet" && styles.tagDiet,
      )}
    >
      {tag.name}
    </span>
  );
}

const styles = stylex.create({
  card: {
    display: "flex",
    flexDirection: "column",
    height: "100%",
    overflow: "hidden",
    borderRadius: 14,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: colors.surface0, ":hover": colors.surface1 },
    backgroundColor: colors.mantle,
    color: colors.ink,
    textDecoration: "none",
  },
  photo: {
    display: "grid",
    placeItems: "center",
    aspectRatio: "4 / 3",
    backgroundColor: `color-mix(in srgb, ${colors.magic} 10%, ${colors.crust})`,
  },
  image: { width: "100%", height: "100%", objectFit: "cover" },
  body: { display: "flex", flexDirection: "column", gap: 8, padding: 14 },
  title: {
    margin: 0,
    fontSize: 15,
    fontWeight: 600,
    lineHeight: 1.3,
    display: "-webkit-box",
    WebkitLineClamp: 2,
    WebkitBoxOrient: "vertical",
    overflow: "hidden",
  },
  meta: { display: "flex", flexWrap: "wrap", alignItems: "center", gap: 6 },
  time: { fontFamily: fonts.mono, fontSize: 12, color: colors.subtext },
  macros: {
    margin: 0,
    fontFamily: fonts.mono,
    fontSize: 12,
    fontVariantNumeric: "tabular-nums",
    color: colors.subtext,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  srOnly: {
    position: "absolute",
    width: 1,
    height: 1,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
  },
  tag: {
    fontSize: 12,
    fontWeight: 500,
    paddingBlock: 2,
    paddingInline: 8,
    borderRadius: 999,
    backgroundColor: colors.surface0,
    color: colors.ink,
  },
  tagMeal: { backgroundColor: `color-mix(in srgb, ${colors.tips} 24%, transparent)` },
  tagDiet: { backgroundColor: `color-mix(in srgb, ${colors.fresh} 24%, transparent)` },
  row: {
    display: "grid",
    gridTemplateColumns: {
      default: "minmax(0, 1fr) auto 72px",
      "@media (max-width: 640px)": "minmax(0, 1fr) 64px",
    },
    alignItems: "center",
    gap: 12,
    minHeight: 52,
    paddingInline: 12,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: colors.surface0,
    borderRadius: 8,
    backgroundColor: { default: "transparent", ":hover": colors.mantle },
    color: colors.ink,
    textDecoration: "none",
  },
  rowTitle: {
    fontSize: 15,
    fontWeight: 500,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  rowTags: {
    display: { default: "flex", "@media (max-width: 640px)": "none" },
    gap: 6,
  },
  rowTime: { textAlign: "end" },
});
