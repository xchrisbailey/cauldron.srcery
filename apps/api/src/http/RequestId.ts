import { Effect } from "effect";
import { HttpRouter, HttpServerRequest, HttpServerResponse } from "effect/http";
import { shapeErrors } from "./ErrorShape.ts";

const HEADER = "x-request-id";
const valid = /^[A-Za-z0-9._-]{8,128}$/;

// Accepts a well-formed incoming request id (from a proxy) or makes one, then
// puts it on the span, the logs and the response. Failures are shaped first
// (see ErrorShape) so error responses, including unknown routes, carry the id too.
export const RequestId = HttpRouter.middleware(
  (app) =>
    Effect.gen(function* () {
      const request = yield* HttpServerRequest.HttpServerRequest;
      const incoming = request.headers[HEADER];
      const id = incoming && valid.test(incoming) ? incoming : crypto.randomUUID();
      yield* Effect.annotateCurrentSpan("http.request_id", id);
      const response = yield* shapeErrors(app).pipe(Effect.annotateLogs("requestId", id));
      return HttpServerResponse.setHeader(response, HEADER, id);
    }),
  { global: true },
);
