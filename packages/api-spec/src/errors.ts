import {
  Conflict,
  Forbidden,
  InvalidRequest,
  NotFound,
  TooManyRequests,
  Unauthorized,
  Unavailable,
} from "@cauldron/shared";
import { Schema, SchemaTransformation } from "effect";
import { HttpApiSchema } from "effect/http-api";

// The one place domain errors meet HTTP: each error gets a status code and a
// stable `code`, and is sent as `{ error: { code, message } }`. The same
// schemas decode the shape back into the error class in the typed client.

export const ErrorBody = <Code extends string>(code: Code) =>
  Schema.Struct({
    error: Schema.Struct({
      code: Schema.Literal(code),
      message: Schema.String,
    }),
  });

type MessageError = Schema.Top & {
  readonly Type: { readonly _tag: string; readonly message: string };
  readonly Encoded: { readonly _tag: string; readonly message: string };
};

const wire = <S extends MessageError, Code extends string>(
  errorClass: S,
  tag: S["Type"]["_tag"],
  code: Code,
  status: number,
) =>
  ErrorBody(code).pipe(
    Schema.decodeTo(
      errorClass,
      SchemaTransformation.transform({
        decode: ({ error }) => ({ _tag: tag, message: error.message }) as S["Encoded"],
        encode: (e) => ({ error: { code, message: e.message } }) as const,
      }),
    ),
    HttpApiSchema.status(status),
  );

export const UnauthorizedError = wire(Unauthorized, "Unauthorized", "unauthorized", 401);
export const ForbiddenError = wire(Forbidden, "Forbidden", "forbidden", 403);
export const NotFoundError = wire(NotFound, "NotFound", "not_found", 404);
export const ConflictError = wire(Conflict, "Conflict", "conflict", 409);
export const InvalidRequestError = wire(InvalidRequest, "InvalidRequest", "invalid_request", 422);
export const UnavailableError = wire(Unavailable, "Unavailable", "unavailable", 503);

export const TooManyRequestsError = Schema.Struct({
  error: Schema.Struct({
    code: Schema.Literal("too_many_requests"),
    message: Schema.String,
    retryAfterSeconds: Schema.Int,
  }),
}).pipe(
  Schema.decodeTo(
    TooManyRequests,
    SchemaTransformation.transform({
      decode: ({ error }) => ({
        _tag: "TooManyRequests" as const,
        message: error.message,
        retryAfterSeconds: error.retryAfterSeconds,
      }),
      encode: (e) => ({
        error: {
          code: "too_many_requests" as const,
          message: e.message,
          retryAfterSeconds: e.retryAfterSeconds,
        },
      }),
    }),
  ),
  HttpApiSchema.status(429),
);

/** Codes for failures that don't come from a domain error (bad input, unknown routes, bugs). */
export const InternalErrorCodes = {
  invalidRequest: "invalid_request",
  notFound: "not_found",
  internal: "internal",
} as const;
