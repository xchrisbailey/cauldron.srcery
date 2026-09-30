import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { getSession } from "../lib/session";

// Every route under _authed needs a signed-in user; others are sent to sign in
// and brought back afterwards.
export const Route = createFileRoute("/_authed")({
  beforeLoad: async ({ location }) => {
    const session = await getSession();
    if (!session) throw redirect({ to: "/sign-in", search: { redirect: location.href } });
    return { session };
  },
  component: Outlet,
});
