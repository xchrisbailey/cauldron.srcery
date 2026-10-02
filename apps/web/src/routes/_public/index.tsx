import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { createFileRoute, redirect } from "@tanstack/react-router";
import { Schema } from "effect";
import { Lockup } from "../../components/Lockup";
import { ButtonLink } from "../../components/ui";
import { sessionQuery } from "../../lib/session";
import { SearchFlag } from "../../lib/search";
import { colors } from "../../styles/tokens.stylex";
import { pageTitle } from "../../lib/page-title";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({ verified: SearchFlag, error: Schema.optional(Schema.String) }),
);

// Signed-in visitors go straight to their recipes. Email verification links
// land here (`?verified=1`, or `?error=` when the link was bad), so pass those on.
export const Route = createFileRoute("/_public/")({
  head: () => pageTitle(),
  validateSearch: Search,
  beforeLoad: async ({ search, context }) => {
    const session = await context.queryClient.fetchQuery(sessionQuery);
    if (session) {
      throw redirect({
        to: "/recipes",
        search: { verified: search.verified ? 1 : undefined, error: search.error },
      });
    }
    if (search.error) throw redirect({ to: "/sign-in", search: { error: search.error } });
  },
  component: Landing,
});

function Landing() {
  return (
    <section {...stylex.props(styles.hero)}>
      <h1 {...stylex.props(styles.title)} aria-label={copy.ui.appName.text}>
        <Lockup size="hero" />
      </h1>
      <p {...stylex.props(styles.tagline)}>{copy.ui.tagline.text}</p>
      <div {...stylex.props(styles.actions)}>
        <ButtonLink to="/sign-up">{copy.auth.signUp.text}</ButtonLink>
        <ButtonLink to="/sign-in" variant="secondary">
          {copy.auth.signIn.text}
        </ButtonLink>
      </div>
    </section>
  );
}

const styles = stylex.create({
  hero: {
    width: "100%",
    maxWidth: 720,
    display: "flex",
    flexDirection: "column",
    gap: 24,
    paddingBlock: { default: 24, "@media (min-width: 768px)": 64 },
  },
  title: { margin: 0 },
  tagline: {
    margin: 0,
    maxWidth: "40ch",
    fontSize: "clamp(1.1rem, 2.4vw, 1.35rem)",
    color: colors.subtext,
    textWrap: "pretty",
  },
  actions: { display: "flex", flexWrap: "wrap", gap: 10 },
});
