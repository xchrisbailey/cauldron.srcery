import { Context } from "effect";
import { HttpApiMiddleware } from "effect/http-api";
import type { User } from "@cauldron/shared";
import { ForbiddenError, UnauthorizedError } from "./errors.ts";

export class CurrentUser extends Context.Service<CurrentUser, User>()(
  "cauldron/api-spec/CurrentUser",
) {}

// Resolves the Better Auth session (cookie on web, bearer token on iOS) and
// provides CurrentUser. Cookie-authenticated writes must come from the web
// origin (a CSRF guard). The server implementation lives in apps/api.
export class Authorization extends HttpApiMiddleware.Service<
  Authorization,
  { provides: CurrentUser; requires: never }
>()("cauldron/api-spec/Authorization", {
  error: [UnauthorizedError, ForbiddenError],
}) {}
