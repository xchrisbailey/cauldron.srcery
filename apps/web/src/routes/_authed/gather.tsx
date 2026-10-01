import { copy } from "@cauldron/shared";
import { createFileRoute } from "@tanstack/react-router";
import { EmptyState, PageHeader } from "../../components/ui";

// The list arrives with #19.
export const Route = createFileRoute("/_authed/gather")({ component: Gather });

function Gather() {
  return (
    <>
      <PageHeader title={copy.gather.title.text} />
      <EmptyState message={copy.gather.empty.text} />
    </>
  );
}
