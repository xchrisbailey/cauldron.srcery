import { Api } from "@cauldron/api-spec";
import { Effect } from "effect";
import { HttpServerResponse } from "effect/http";
import { HttpApiBuilder } from "effect/http-api";
import { Photos } from "../Photos.ts";
import { owned } from "./owned.ts";

// Storage and database failures are unexpected here: defects, logged as 500s.
export const PhotosHandlers = HttpApiBuilder.group(
  Api,
  "photos",
  Effect.fn(function* (handlers) {
    const photos = yield* Photos;
    return handlers
      .handle("startUpload", ({ payload }) => owned((owner) => photos.startUpload(owner, payload)))
      .handle("receiveUpload", ({ params, payload }) =>
        owned((owner) => photos.receiveUpload(owner, params.id, payload)),
      )
      .handle("finishUpload", ({ payload }) =>
        owned((owner) => photos.finishUpload(owner, payload.uploadId)),
      )
      .handle("fromUrl", ({ payload }) => owned((owner) => photos.fromUrl(owner, payload.url)))
      .handle("variant", ({ params }) =>
        owned((owner) => photos.read(owner, params.id, params.variant)).pipe(
          // A photo's variants never change, so the browser can keep them.
          Effect.map((bytes) =>
            HttpServerResponse.uint8Array(bytes, {
              contentType: "image/webp",
              headers: { "cache-control": "private, max-age=31536000, immutable" },
            }),
          ),
        ),
      );
  }),
);
