import { Api, CurrentUser } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpServerResponse } from "effect/http";
import { HttpApiBuilder } from "effect/http-api";
import { Photos } from "../Photos.ts";

// Storage and database failures are unexpected here: defects, logged as 500s.
export const PhotosHandlers = HttpApiBuilder.group(
  Api,
  "photos",
  Effect.fn(function* (handlers) {
    const photos = yield* Photos;
    return handlers
      .handle("startUpload", ({ payload }) =>
        CurrentUser.use((user) => photos.startUpload(user.id, payload)).pipe(
          Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
        ),
      )
      .handle("receiveUpload", ({ params, payload }) =>
        CurrentUser.use((user) => photos.receiveUpload(user.id, params.id, payload)).pipe(
          Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
        ),
      )
      .handle("finishUpload", ({ payload }) =>
        CurrentUser.use((user) => photos.finishUpload(user.id, payload.uploadId)).pipe(
          Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
        ),
      )
      .handle("fromUrl", ({ payload }) =>
        CurrentUser.use((user) => photos.fromUrl(user.id, payload.url)).pipe(
          Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
        ),
      )
      .handle("variant", ({ params }) =>
        CurrentUser.use((user) => photos.read(user.id, params.id, params.variant)).pipe(
          // A photo's variants never change, so the browser can keep them.
          Effect.map((bytes) =>
            HttpServerResponse.uint8Array(bytes, {
              contentType: "image/webp",
              headers: { "cache-control": "private, max-age=31536000, immutable" },
            }),
          ),
          Effect.catchTags({ DbError: Effect.die, StorageError: Effect.die }),
        ),
      );
  }),
);
