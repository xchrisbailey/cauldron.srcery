import { createFileRoute, Outlet } from "@tanstack/react-router";
import { PublicShell } from "../components/PublicShell";

// The landing page and the account screens, for visitors who aren't signed in.
export const Route = createFileRoute("/_public")({
  component: () => (
    <PublicShell>
      <Outlet />
    </PublicShell>
  ),
});
