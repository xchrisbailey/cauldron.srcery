import { copy } from "@cauldron/shared";
import { useQueryErrorResetBoundary } from "@tanstack/react-query";
import { type ErrorComponentProps, useRouter } from "@tanstack/react-router";
import { useEffect } from "react";
import { Button, EmptyState } from "./ui";

/**
 * What a route shows when it throws while loading or rendering, in place of
 * the router's own unstyled box. Try again clears failed queries and reloads
 * the route.
 */
export function RouteError({ error }: ErrorComponentProps) {
  const router = useRouter();
  const queryReset = useQueryErrorResetBoundary();
  useEffect(() => {
    if (import.meta.env.DEV) console.error(error);
    queryReset.reset();
  }, [error, queryReset]);
  return (
    <EmptyState
      message={copy.errors.internal.text}
      actions={
        <Button variant="secondary" onClick={() => void router.invalidate()}>
          {copy.ui.tryAgain.text}
        </Button>
      }
    />
  );
}
