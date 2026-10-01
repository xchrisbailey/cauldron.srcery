import { createFileRoute, Outlet } from "@tanstack/react-router";
import { requireSignIn } from "../lib/guard";

// Signed-in pages that take the whole screen, without the app shell: cook mode.
export const Route = createFileRoute("/_kitchen")({
  beforeLoad: requireSignIn,
  component: Outlet,
});
