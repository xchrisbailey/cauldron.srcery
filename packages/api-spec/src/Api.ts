import { User } from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApi, HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { UnavailableError } from "./errors.ts";
import { ImportsApi } from "./Imports.ts";
import { PhotosApi } from "./Photos.ts";
import { RecipesApi, TagsApi } from "./Recipes.ts";

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
}) {}

export class SystemApi extends HttpApiGroup.make("system", { topLevel: true })
  .add(
    HttpApiEndpoint.get("health", "/health", { success: Health, error: UnavailableError }),
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
  .prefix("/v1")
  .annotateMerge(OpenApi.annotations({ title: "Cauldron API" })) {}
