import {
  Photo,
  PhotoFinishInput,
  PhotoFromUrlInput,
  PhotoId,
  PhotoUpload,
  PhotoUploadInput,
  PhotoVariant,
} from "@cauldron/shared";
import { Schema } from "effect";
import { HttpApiEndpoint, HttpApiGroup, HttpApiSchema, OpenApi } from "effect/http-api";
import { Authorization } from "./Authorization.ts";
import { InvalidRequestError, NotFoundError } from "./errors.ts";
import { RateLimit, RateLimitPolicy } from "./RateLimit.ts";

const Bytes = (contentType: string) =>
  Schema.Uint8Array.pipe(HttpApiSchema.asUint8Array({ contentType }));

export class PhotosApi extends HttpApiGroup.make("photos")
  .add(
    HttpApiEndpoint.post("startUpload", "/uploads", {
      payload: PhotoUploadInput,
      success: PhotoUpload,
    }).annotate(
      OpenApi.Description,
      "Where to PUT the original: storage directly when it can sign a URL, otherwise /photos/uploads/{id}.",
    ),
    HttpApiEndpoint.put("receiveUpload", "/uploads/:id", {
      params: { id: Schema.String.check(Schema.isUUID()) },
      payload: Bytes("application/octet-stream"),
      success: HttpApiSchema.NoContent,
      error: InvalidRequestError,
    }),
    HttpApiEndpoint.post("finishUpload", "/", {
      payload: PhotoFinishInput,
      success: Photo,
      error: InvalidRequestError,
    }).annotate(OpenApi.Description, "Resizes the uploaded original into WebP variants."),
    HttpApiEndpoint.post("fromUrl", "/from-url", {
      payload: PhotoFromUrlInput,
      success: Photo,
      error: InvalidRequestError,
    })
      .middleware(RateLimit)
      .annotate(RateLimitPolicy, { limit: 20, window: "1 minute" })
      .annotate(
        OpenApi.Description,
        "Downloads a photo from a source URL on the server, for imports.",
      ),
    HttpApiEndpoint.get("variant", "/:id/:variant", {
      params: { id: PhotoId, variant: PhotoVariant },
      success: Bytes("image/webp"),
      error: NotFoundError,
    }),
  )
  .middleware(Authorization)
  .prefix("/photos")
  .annotateMerge(OpenApi.annotations({ title: "Photos" })) {}
