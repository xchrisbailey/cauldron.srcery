import { copy } from "@cauldron/shared";
import { createFileRoute } from "@tanstack/react-router";
import { Schema } from "effect";
import { ButtonLink, EmptyState, FormMessage, PageHeader } from "../../../components/ui";
import { SearchFlag } from "../../../lib/search";

const Search = Schema.toStandardSchemaV1(
  Schema.Struct({ verified: SearchFlag, error: Schema.optional(Schema.String) }),
);

// Where signed-in visitors land. The library itself arrives with #11.
export const Route = createFileRoute("/_authed/recipes/")({
  validateSearch: Search,
  component: Recipes,
});

function Recipes() {
  const { verified, error } = Route.useSearch();
  const conjure = <ButtonLink to="/recipes/new">{copy.recipes.conjure.text}</ButtonLink>;
  return (
    <>
      <PageHeader title={copy.nav.recipes.text} actions={conjure} />
      {error ? (
        <FormMessage tone="error">{copy.auth.linkExpired.text}</FormMessage>
      ) : verified ? (
        <FormMessage tone="info">{copy.auth.emailVerified.text}</FormMessage>
      ) : null}
      <EmptyState message={copy.recipes.empty.text} />
    </>
  );
}
