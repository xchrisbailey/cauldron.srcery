import * as stylex from "@stylexjs/stylex";
import { copy } from "@cauldron/shared";
import { createFileRoute } from "@tanstack/react-router";
import { PageHeader, Skeleton } from "../../../components/ui";

// The recipe editor arrives with #9; until then the shell links here.
export const Route = createFileRoute("/_authed/recipes/new")({ component: Conjure });

function Conjure() {
  return (
    <>
      <PageHeader title={copy.recipes.conjure.text} />
      <div aria-busy="true" aria-label={copy.ui.loading.text} {...stylex.props(styles.rows)}>
        <Skeleton height={40} />
        <Skeleton width="60%" />
        <Skeleton width="80%" />
        <Skeleton width="45%" />
      </div>
    </>
  );
}

const styles = stylex.create({ rows: { display: "grid", gap: 12, maxWidth: 560 } });
