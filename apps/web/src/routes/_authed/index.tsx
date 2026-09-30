import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { Schema } from "effect";
import { SearchFlag } from "../../lib/search";
import { AuthCard, FormMessage, Stack, TextLink } from "../../components/ui";
import { callApi } from "../../lib/api";
import { fonts } from "../../styles/tokens.stylex";

const Search = Schema.toStandardSchemaV1(Schema.Struct({ verified: SearchFlag }));

// A placeholder home until the shell (#7) and the recipe box land.
export const Route = createFileRoute("/_authed/")({ validateSearch: Search, component: Home });

function Home() {
  const { session } = Route.useRouteContext();
  const { verified } = Route.useSearch();
  // Proves the typed client works signed in; the session above came from the server.
  const me = useQuery({ queryKey: ["me"], queryFn: () => callApi((c) => c.account.me()) });
  return (
    <AuthCard title="Cauldron">
      {verified ? <FormMessage tone="info">{copy.auth.emailVerified.text}</FormMessage> : null}
      <Stack>
        <p data-testid="signed-in">
          {copy.auth.signedInAs.text} <strong>{me.data?.name ?? session.user.name}</strong>{" "}
          <span {...stylex.props(styles.mono)}>{session.user.email}</span>
        </p>
        <TextLink to="/account">{copy.auth.account.text}</TextLink>
      </Stack>
    </AuthCard>
  );
}

const styles = stylex.create({ mono: { fontFamily: fonts.mono, fontSize: 13 } });
