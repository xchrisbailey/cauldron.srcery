import { CurrentUser } from "@cauldron/api-spec";
import type { UserId } from "@cauldron/shared";
import { Effect } from "effect";
import type { DbError } from "../Db.ts";
import type { StorageError } from "../Storage.ts";

// Runs an owner-scoped handler body as the current user. Database and storage
// failures are bugs or outages, never part of an endpoint's contract, so they
// become defects (which the error shape renders as a logged, redacted 500);
// every other error still reaches the endpoint's declared errors. The cast is
// there because catchTags can't narrow a generic E.
export const owned = <A, E, R>(
  f: (owner: UserId) => Effect.Effect<A, E, R>,
): Effect.Effect<A, Exclude<E, DbError | StorageError>, R | CurrentUser> =>
  CurrentUser.use((user) => f(user.id)).pipe(
    Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
  ) as Effect.Effect<A, Exclude<E, DbError | StorageError>, R | CurrentUser>;
