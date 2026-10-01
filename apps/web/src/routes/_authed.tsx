import { createFileRoute, Outlet } from "@tanstack/react-router";
import { AppShell } from "../components/AppShell";
import { requireSignIn } from "../lib/guard";

// Every route under _authed needs a signed-in user and sits in the app shell.
export const Route = createFileRoute("/_authed")({
  beforeLoad: requireSignIn,
  component: () => (
    <AppShell>
      <Outlet />
    </AppShell>
  ),
});
