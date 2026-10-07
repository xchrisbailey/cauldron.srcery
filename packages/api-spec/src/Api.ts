import { User } from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApi, HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { UnavailableError } from "./errors.ts";
import { GatherApi } from "./Gather.ts";
import { ImportsApi } from "./Imports.ts";
import { PhotosApi } from "./Photos.ts";
import { PlanApi } from "./Plan.ts";
import { RateLimit, RateLimitPolicy } from "./RateLimit.ts";
import { RecipesApi, TagsApi } from "./Recipes.ts";
import { TrackerApi } from "./Tracker.ts";

export class Health extends Schema.Class<Health>("Health")({
  status: Schema.Literal("ok"),
  database: Schema.Literal("ok"),
}) {}

export class Version extends Schema.Class<Version>("Version")({
  version: Schema.String,
  commit: Schema.NullOr(Schema.String),
}) {}

export class SignInOptions extends Schema.Class<SignInOptions>("SignInOptions")({
  google: Schema.Boolean,
  apple: Schema.Boolean,
  /** A local OIDC provider standing in for Google and Apple in development. */
  dev: Schema.Boolean,
  /** Whether new accounts can be created at all. False hides the sign-up screens. */
  signUp: Schema.Boolean,
}) {}

export class SystemApi extends HttpApiGroup.make("system", { topLevel: true })
  .add(
    // Anonymous and it queries the database, so it is limited per client address.
    HttpApiEndpoint.get("health", "/health", { success: Health, error: UnavailableError })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 60, window: "1 minute" }),
    HttpApiEndpoint.get("version", "/version", { success: Version }),
    HttpApiEndpoint.get("signInOptions", "/sign-in-options", { success: SignInOptions }),
  )
  .annotateMerge(OpenApi.annotations({ title: "System" })) {}

export class AccountApi extends HttpApiGroup.make("account")
  .add(HttpApiEndpoint.get("me", "/me", { success: User }))
  .middleware(Authorization)
  .prefix("/account")
  .annotateMerge(OpenApi.annotations({ title: "Account" })) {}

export class Api extends HttpApi.make("cauldron")
  .add(SystemApi)
  .add(AccountApi)
  .add(RecipesApi)
  .add(TagsApi)
  .add(PhotosApi)
  .add(ImportsApi)
  .add(PlanApi)
  .add(GatherApi)
  .add(TrackerApi)
  .prefix("/v1")
  .annotateMerge(OpenApi.annotations({ title: "Cauldron API" })) {}
