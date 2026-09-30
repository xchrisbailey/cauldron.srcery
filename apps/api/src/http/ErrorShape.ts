import { copy } from "@cauldron/shared";
import { InternalErrorCodes } from "@cauldron/api-spec";
import { Cause, Effect } from "effect";
import { DbError, redactDbError } from "../Db.ts";
import { HttpRouter, HttpServerError, HttpServerResponse } from "effect/http";

// Domain errors are encoded by their endpoint schemas (packages/api-spec/src/errors.ts).
// This catches everything else (bad input, unknown routes, bugs) and gives it
// the same `{ error: { code, message } }` shape instead of an empty body.
const bodyFor = (status: number) => {
  if (status === 404)
    return { code: InternalErrorCodes.notFound, message: copy.errors.notFound.text };
  if (status >= 400 && status < 500)
    return { code: InternalErrorCodes.invalidRequest, message: copy.errors.invalidRequest.text };
  return { code: InternalErrorCodes.internal, message: copy.errors.internal.text };
};

/**
 * Logs an unhandled failure. Database errors are reduced to their code and
 * message: Drizzle's own error text includes the query parameters (emails,
 * tokens), which must not reach the logs.
 */
export const logFailure = (cause: Cause.Cause<unknown>) => {
  const isDb = (reason: Cause.Reason<unknown>) =>
    (Cause.isFailReason(reason) && reason.error instanceof DbError) ||
    (Cause.isDieReason(reason) && reason.defect instanceof DbError);
  const dbErrors = cause.reasons
    .filter(isDb)
    .map((reason) =>
      redactDbError(
        Cause.isFailReason(reason)
          ? (reason.error as DbError)
          : ((reason as Cause.Die).defect as DbError),
      ),
    );
  if (dbErrors.length === 0) return Effect.logError("Unhandled failure", cause);
  const rest = Cause.fromReasons(cause.reasons.filter((reason) => !isDb(reason)));
  return Effect.logError("Unhandled database failure", dbErrors).pipe(
    Effect.andThen(
      rest.reasons.length > 0 ? Effect.logError("Unhandled failure", rest) : Effect.void,
    ),
  );
};

export const shapeErrors = <E, R>(
  app: Effect.Effect<HttpServerResponse.HttpServerResponse, E, R>,
) =>
  Effect.catchCause(app, (cause) =>
    Effect.gen(function* () {
      if (Cause.hasInterruptsOnly(cause)) return yield* Effect.failCause(cause);
      const [response] = yield* HttpServerError.causeResponse(cause);
      if (response.status >= 500) yield* logFailure(cause);
      if (response.body._tag !== "Empty" || response.status < 400 || response.status === 499) {
        return response;
      }
      return HttpServerResponse.jsonUnsafe(
        { error: bodyFor(response.status) },
        { status: response.status, headers: response.headers },
      );
    }),
  );

export const ErrorShape = HttpRouter.middleware(shapeErrors, { global: true });
