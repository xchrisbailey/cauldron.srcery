import { Layer } from "effect";
import { Auth } from "./Auth.ts";
import { Db } from "./Db.ts";
import { ApiRoutes } from "./http/Api.ts";
import { AuthRoute } from "./http/AuthRoute.ts";

export const Services = Auth.layer.pipe(Layer.provideMerge(Db.layer));

export const Routes = Layer.mergeAll(ApiRoutes, AuthRoute).pipe(Layer.provide(Services));
