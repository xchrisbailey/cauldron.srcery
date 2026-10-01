import { copy } from "@cauldron/shared";
import { createFileRoute } from "@tanstack/react-router";
import { EmptyState, PageHeader } from "../../components/ui";

// The planner arrives with #18.
export const Route = createFileRoute("/_authed/week")({ component: Week });

function Week() {
  return (
    <>
      <PageHeader title={copy.week.title.text} />
      <EmptyState message={copy.week.empty.text} />
    </>
  );
}
