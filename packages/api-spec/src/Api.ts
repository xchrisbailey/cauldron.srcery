import { Schema } from "effect";
import { HttpApi, HttpApiEndpoint, HttpApiGroup, OpenApi } from "effect/http-api";
import { User } from "@cauldron/shared";
import { Authorization } from "./Authorization.ts";

export class Health extends Schema.Class<Health>("Health")({
  status: Schema.Literal("ok"),
}) {}

export class SystemApi extends HttpApiGroup.make("system", { topLevel: true }).add(
  HttpApiEndpoint.get("health", "/health", { success: Health }),
) {}

export class AccountApi extends HttpApiGroup.make("account")
  .add(HttpApiEndpoint.get("me", "/me", { success: User }))
  .middleware(Authorization)
  .prefix("/account") {}

export class Api extends HttpApi.make("cauldron")
  .add(SystemApi)
  .add(AccountApi)
  .prefix("/v1")
  .annotateMerge(OpenApi.annotations({ title: "Cauldron API" })) {}
